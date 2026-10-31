package com.ayahreel.app

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import java.util.concurrent.Executors

/**
 * The listening model on the phone (channel "ayahreel/listen"): ONNX
 * Runtime with one session at a time, every call on one background
 * thread of its own, so a long run never holds the UI thread (Android
 * would call that an ANR).
 *
 *  - load {path, threads}: opens the model file (again only if it changed)
 *  - run {wave: Float32List, 16 kHz mono}: {logp: Float32List, frames, width}
 *  - unload: lets the session and its memory go
 */
class ListenBridge(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "ayahreel/listen")
    private val worker = Executors.newSingleThreadExecutor { r ->
        Thread(r, "listen").apply { priority = Thread.NORM_PRIORITY - 1 }
    }
    private val main = Handler(Looper.getMainLooper())
    private var env: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var loadedPath: String? = null

    init {
        channel.setMethodCallHandler(this)
    }

    private fun answer(result: MethodChannel.Result, value: Any?) =
        main.post { result.success(value) }

    private fun fail(result: MethodChannel.Result, code: String, t: Throwable) =
        main.post { result.error(code, t.message ?: t.javaClass.simpleName, null) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> {
                val path = call.argument<String>("path")
                val threads = call.argument<Int>("threads") ?: 2
                if (path == null) {
                    result.error("load", "no path", null)
                    return
                }
                worker.execute {
                    try {
                        if (loadedPath != path || session == null) {
                            session?.close()
                            session = null
                            loadedPath = null
                            val e = env ?: OrtEnvironment.getEnvironment().also { env = it }
                            val options = OrtSession.SessionOptions().apply {
                                setIntraOpNumThreads(threads)
                                setInterOpNumThreads(1)
                                // A reduced (minimal) build runs the ORT-format
                                // model as converted, optimized already.
                                try {
                                    setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                                } catch (_: Throwable) {
                                }
                            }
                            session = e.createSession(path, options)
                            loadedPath = path
                        }
                        answer(result, mapOf("ok" to true))
                    } catch (t: Throwable) {
                        fail(result, "load", t)
                    }
                }
            }
            "run" -> {
                val wave = call.argument<FloatArray>("wave")
                if (wave == null) {
                    result.error("run", "no wave", null)
                    return
                }
                worker.execute {
                    try {
                        val s = session ?: throw IllegalStateException("not loaded")
                        val e = env ?: throw IllegalStateException("no environment")
                        OnnxTensor.createTensor(
                            e, FloatBuffer.wrap(wave), longArrayOf(1, wave.size.toLong())
                        ).use { input ->
                            s.run(mapOf("wave" to input)).use { out ->
                                val v = out.get(0) as OnnxTensor
                                val shape = v.info.shape
                                val fb = v.floatBuffer
                                val logp = FloatArray(fb.remaining())
                                fb.get(logp)
                                answer(
                                    result,
                                    mapOf(
                                        "logp" to logp,
                                        "frames" to shape[0].toInt(),
                                        "width" to shape[1].toInt(),
                                    ),
                                )
                            }
                        }
                    } catch (t: Throwable) {
                        fail(result, "run", t)
                    }
                }
            }
            "unload" -> worker.execute {
                try {
                    session?.close()
                } catch (_: Throwable) {
                }
                session = null
                loadedPath = null
                answer(result, true)
            }
            else -> result.notImplemented()
        }
    }
}

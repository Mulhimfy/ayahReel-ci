package com.ayahreel.app

import android.app.ActivityManager
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import android.os.RemoteException
import android.util.Log
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFmpegKitConfig
import com.antonkarpenko.ffmpegkit.Level
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Runs a save's FFmpeg encodes in a process of their own, ":render".
 *
 * An encode is the biggest and riskiest thing the app does: hundreds of
 * MB on phones that have little, and a device encoder whose vendor code
 * has taken the whole app down with it (see EXPORT_MEMORY.md). Run in
 * the app, either ended the same way: the app vanished mid-save. Run
 * here, a crash or a low-memory kill ends this process and nothing
 * else. The app sees the encode die and plans it again, smaller or on
 * x264, behind the same progress bar.
 *
 * And the system is told which to kill first. Bound without
 * BIND_IMPORTANT, this process ranks as visible while the app ranks as
 * foreground, so when memory runs out it is the encode that goes.
 *
 * Three messages: RUN (an id and FFmpeg's arguments) and CANCEL from
 * the app, DONE (the id, the return code, the end of the log) back. One
 * encode at a time, as the renderer runs them.
 */
class RenderService : Service() {
    private lateinit var worker: HandlerThread
    private lateinit var work: Handler

    private val inbox = Messenger(Handler(Looper.getMainLooper()) { msg ->
        onMessage(msg)
        true
    })

    override fun onCreate() {
        super.onCreate()
        worker = HandlerThread("render").also { it.start() }
        work = Handler(worker.looper)
        try {
            // As the app sets them (ffmpeg_setup.dart): warnings and up
            // are all anyone reads, and every line kept is heap.
            FFmpegKitConfig.setLogLevel(Level.AV_LOG_WARNING)
            FFmpegKitConfig.setSessionHistorySize(4)
        } catch (t: Throwable) {
            Log.w(TAG, "config: $t")
        }
    }

    override fun onBind(intent: Intent): IBinder = inbox.binder

    override fun onDestroy() {
        worker.quitSafely()
        super.onDestroy()
    }

    private fun onMessage(msg: Message) {
        when (msg.what) {
            RUN -> {
                val id = msg.arg1
                val args = msg.data.getStringArray(KEY_ARGS) ?: emptyArray()
                val reply = msg.replyTo
                work.post { run(id, args, reply) }
            }
            CANCEL -> try {
                FFmpegKit.cancel()
            } catch (t: Throwable) {
                Log.w(TAG, "cancel: $t")
            }
        }
    }

    private fun run(id: Int, args: Array<String>, reply: Messenger?) {
        var code: Int
        var logs: String
        try {
            val session = FFmpegKit.executeWithArguments(args)
            code = session.returnCode?.value ?: NO_CODE
            logs = session.allLogsAsString ?: ""
        } catch (t: Throwable) {
            // FFmpeg never ran here: the app runs it itself instead.
            code = UNAVAILABLE
            logs = "render process: $t"
        }
        val out = Message.obtain(null, DONE, id, code)
        out.data = Bundle().apply { putString(KEY_LOGS, tail(logs)) }
        try {
            reply?.send(out)
        } catch (e: RemoteException) {
            Log.w(TAG, "the app is gone: $e")
        }
    }

    companion object {
        private const val TAG = "RenderService"
        const val RUN = 1
        const val CANCEL = 2
        const val DONE = 3
        const val KEY_ARGS = "args"
        const val KEY_LOGS = "logs"

        /** FFmpeg could not be started in this process at all. */
        const val UNAVAILABLE = -1001

        /** FFmpeg ended without a return code. */
        const val NO_CODE = -1002

        /** The process died under the encode: a crash or a kill. */
        const val DIED = -1003

        /**
         * A Binder transaction carries about a megabyte between every
         * process on the phone; the log's end is where FFmpeg says what
         * broke, and all the renderer reads.
         */
        private const val LOG_LIMIT = 48 * 1024

        fun tail(s: String) =
            if (s.length <= LOG_LIMIT) s else s.substring(s.length - LOG_LIMIT)
    }
}

/**
 * The app's side of [RenderService], behind the ayahreel/render channel:
 * binds it, hands it encodes, keeps what comes back until Dart polls for
 * it, and notices when the render process dies under an encode.
 *
 * Every call answers on the main thread, where the replies arrive too,
 * so nothing here needs a lock.
 */
object RenderClient {
    private const val CONNECT_LIMIT_MS = 4000L
    private const val IDLE_UNBIND_MS = 30000L

    private lateinit var app: Context
    private val main = Handler(Looper.getMainLooper())

    private var service: Messenger? = null
    private var bound = false
    private val waiting = mutableListOf<() -> Unit>()
    private val running = mutableSetOf<Int>()
    private val done = mutableMapOf<Int, Map<String, Any>>()
    private var nextId = 1

    private val replies = Messenger(Handler(Looper.getMainLooper()) { msg ->
        if (msg.what == RenderService.DONE) {
            running.remove(msg.arg1)
            done[msg.arg1] = mapOf(
                "code" to msg.arg2,
                "logs" to (msg.data.getString(RenderService.KEY_LOGS) ?: ""),
            )
            idleLater()
        }
        true
    })

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            service = Messenger(binder)
            flush()
        }

        override fun onServiceDisconnected(name: ComponentName) {
            // The render process died, and every encode in it with it.
            // The binding stays: Android starts the service again and
            // onServiceConnected comes back by itself.
            service = null
            for (id in running) {
                done[id] = mapOf(
                    "code" to RenderService.DIED,
                    "logs" to "the render process died during the encode",
                )
            }
            running.clear()
        }

        override fun onBindingDied(name: ComponentName) {
            onServiceDisconnected(name)
            unbind()
        }

        override fun onNullBinding(name: ComponentName) {
            unbind()
            flush()
        }
    }

    private val idleUnbind = Runnable { if (running.isEmpty()) unbind() }

    fun attach(context: Context, channel: MethodChannel) {
        app = context.applicationContext
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "run" -> {
                val args = call.argument<List<String>>("args")
                if (args == null) {
                    result.success(null)
                    return
                }
                main.removeCallbacks(idleUnbind)
                whenConnected { s ->
                    if (s == null) {
                        result.success(null)
                        return@whenConnected
                    }
                    val id = nextId++
                    val msg = Message.obtain(null, RenderService.RUN, id, 0)
                    msg.data = Bundle().apply {
                        putStringArray(RenderService.KEY_ARGS, args.toTypedArray())
                    }
                    msg.replyTo = replies
                    try {
                        s.send(msg)
                        running += id
                        result.success(id)
                    } catch (e: RemoteException) {
                        result.success(null)
                    }
                }
            }
            "poll" -> {
                val id = call.argument<Int>("id") ?: -1
                val d = done.remove(id)
                result.success(
                    d ?: if (id in running) null else mapOf(
                        "code" to RenderService.DIED,
                        "logs" to "the render process lost the encode",
                    )
                )
            }
            "cancel" -> {
                try {
                    service?.send(Message.obtain(null, RenderService.CANCEL))
                } catch (_: RemoteException) {
                }
                result.success(null)
            }
            // A device encoder that a cancel never reaches holds the
            // whole graph until the process ends: end it.
            "kill" -> result.success(killRenderProcess())
            "pid" -> result.success(renderPid())
            else -> result.notImplemented()
        }
    }

    /** Calls [then] with the service once it is bound, or null if it can't be. */
    private fun whenConnected(then: (Messenger?) -> Unit) {
        service?.let { then(it); return }
        waiting += { then(service) }
        if (!bound) {
            bound = try {
                app.bindService(
                    Intent(app, RenderService::class.java),
                    connection,
                    Context.BIND_AUTO_CREATE,
                )
            } catch (e: Exception) {
                false
            }
            if (!bound) {
                flush()
                return
            }
        }
        main.postDelayed({ if (service == null) flush() }, CONNECT_LIMIT_MS)
    }

    private fun flush() {
        val calls = waiting.toList()
        waiting.clear()
        calls.forEach { it() }
    }

    /** Lets the render process go a while after the last encode. */
    private fun idleLater() {
        main.removeCallbacks(idleUnbind)
        main.postDelayed(idleUnbind, IDLE_UNBIND_MS)
    }

    private fun unbind() {
        if (bound) {
            try {
                app.unbindService(connection)
            } catch (_: Exception) {
            }
        }
        bound = false
        service = null
    }

    private fun renderPid(): Int? {
        val am = app.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val name = "${app.packageName}:render"
        return am?.runningAppProcesses?.firstOrNull { it.processName == name }?.pid
    }

    private fun killRenderProcess(): Boolean {
        val pid = renderPid() ?: return false
        Process.killProcess(pid)
        return true
    }
}

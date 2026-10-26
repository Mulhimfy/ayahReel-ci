package com.ayahreel.app

import android.content.Context
import android.content.pm.PackageManager
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.GLES20
import android.os.Build
import android.os.Process
import android.util.Log
import java.io.File

/**
 * Skia, not Impeller, on phones where Impeller would draw with OpenGL ES.
 *
 * Flutter 3.47.5's Impeller takes Vulkan where it can and falls back to
 * OpenGL ES, and that fallback is behind every native crash and freeze
 * Play has shown since 1.0.8: the snapshot-surface crash
 * (`CreateSnapshotSurface`, `DeviceBufferGLES::OnGetContents`,
 * flutter/flutter#192365), a `RenderPassGLES` segfault on a MediaTek
 * PowerVR phone, and the shader compile at surface creation that held
 * the main thread past an ANR on PowerVR phones (Oppo CPH2269). Skia
 * does none of these. Phones on Vulkan keep Impeller.
 *
 * Two ways to know, both kept per OS build and app install, so an OS or
 * app update asks again:
 *
 * - Before the first engine start, the engine's own rules, copied from
 *   3.47.5 (`android_context_dynamic_impeller.cc`,
 *   `driver_info_vk.cc`): an emulator, a Huawei build, MediaTek with a
 *   vendor API below 32, a known bad board, no Vulkan 1.1, Adreno 650
 *   and older, PowerVR older than CXT, Maleoon, Xclipse below Vulkan 1.3.
 * - After the first frame, the engine's own log line ("Using the
 *   Impeller rendering backend (OpenGLES)."), for phones the rules miss
 *   (a Vulkan driver that fails to start). Those take Skia from the next
 *   launch.
 *
 * The flag is read once per process, by the first engine start
 * (`FlutterLoader`), which in the main process is MainActivity's. Check
 * the rules again on every Flutter upgrade, and drop this class once a
 * Flutter release fixes Impeller's OpenGL ES path. Never throws: when
 * anything fails, Impeller stays, which is how 1.0.9 runs.
 */
object RenderBackend {
    private const val TAG = "AyahReel"
    private const val PREFS = "render_backend"
    private const val KEY = "install"
    private const val REASON = "reason"
    private const val SAW_GLES = "saw_gles"
    private const val LOG_LINE = "Impeller rendering backend"

    /** Once a process: the first frame comes again after each return. */
    @Volatile private var read = false

    /** `ro.product.board` values Impeller refuses Vulkan on (`kBadSocs`). */
    private val badBoards = setOf(
        "exynos7870", "exynos7880", "exynos7872", "exynos7884", "exynos7885",
        "exynos7904", "exynos8890", "exynos8895", "exynos9609", "exynos9610",
        "exynos9611", "exynos9810", "exynos9820", "exynos9825", "rk30sdk",
    )

    /** Adreno names up to 650 in `kAdrenoVersions`: OpenGL ES in Impeller. */
    private val oldAdreno = setOf(
        "504", "505", "506", "508", "509", "510", "512", "530", "540",
        "605", "608", "610", "612", "613", "615", "616", "618", "619L",
        "619", "620", "630", "640", "642L", "642", "643L", "644", "650",
    )

    /** Why this phone should draw with Skia, or null to keep Impeller. */
    fun skiaReason(context: Context): String? = try {
        decide(context)
    } catch (t: Throwable) {
        Log.w(TAG, "render backend not decided", t)
        null
    }

    /**
     * After the first frame of a process that started Impeller: reads
     * the engine's log line on a thread of its own, and if Impeller took
     * OpenGL ES, the next launch draws with Skia.
     */
    fun learn(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || read) return
        read = true
        val app = context.applicationContext
        Thread({
            try {
                val logcat = ProcessBuilder(
                    "logcat", "-d", "-v", "raw", "--pid=${Process.myPid()}",
                ).redirectErrorStream(true).start()
                // The last line wins: a known bad Vulkan driver logs
                // Vulkan first and then falls back to OpenGL ES.
                val line = logcat.inputStream.bufferedReader().useLines { lines ->
                    lines.filter { it.contains(LOG_LINE) }.lastOrNull()
                }
                logcat.destroy()
                if (line != null && line.contains("OpenGLES")) {
                    app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .edit().putBoolean(SAW_GLES, true).apply()
                    Log.i(TAG, "Impeller is on OpenGL ES here: Skia from the next launch")
                }
            } catch (t: Throwable) {
                Log.w(TAG, "render backend not read from the log", t)
            }
        }, "render-backend").start()
    }

    private fun decide(context: Context): String? {
        // Below API 29 the engine draws with Skia already.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val install = installKey(context)
        if (prefs.getString(KEY, null) != install) {
            prefs.edit().clear()
                .putString(KEY, install)
                .putString(REASON, predict(context) ?: "")
                .apply()
        }
        if (prefs.getBoolean(SAW_GLES, false)) return "Impeller took OpenGL ES here before"
        return prefs.getString(REASON, null)?.ifEmpty { null }
    }

    @Suppress("DEPRECATION")
    private fun installKey(context: Context): String {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return "${Build.FINGERPRINT}|${info.lastUpdateTime}"
    }

    /** The engine's own rules, in its order; null where it would try Vulkan. */
    private fun predict(context: Context): String? {
        if (isEmulator()) return "an emulator"
        if (prop("ro.com.google.clientidbase") == "android-huawei") return "a Huawei build"
        val vendorSdk = prop("ro.vendor.build.version.sdk").toIntOrNull() ?: Build.VERSION.SDK_INT
        if (vendorSdk < 32 && prop("ro.vendor.mediatek.platform").isNotEmpty()) {
            return "MediaTek, vendor API $vendorSdk"
        }
        if (Build.BOARD in badBoards) return "board ${Build.BOARD}"
        val pm = context.packageManager
        if (!pm.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, VULKAN_1_1)) {
            return "no Vulkan 1.1"
        }
        val gpu = glRenderer() ?: return null
        val vulkan13 = pm.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, VULKAN_1_3)
        return if (usesGles(gpu, vulkan13)) gpu else null
    }

    /** From the GPU's name: true where Impeller turns Vulkan down. */
    internal fun usesGles(gpu: String, vulkan13: Boolean): Boolean = when {
        gpu.contains("Adreno (TM) ") -> gpu.substringAfter("Adreno (TM) ").trim() in oldAdreno
        gpu.contains("PowerVR") -> !gpu.contains("CXT") && !gpu.contains("DXT")
        gpu.contains("Maleoon") -> true
        gpu.contains("Xclipse") -> !vulkan13
        else -> false
    }

    private const val VULKAN_1_1 = 0x401000
    private const val VULKAN_1_3 = 0x403000

    private fun isEmulator(): Boolean =
        Build.HARDWARE in setOf("goldfish", "ranchu", "qemu") ||
            Build.MODEL.contains("gphone") ||
            File("/dev/qemu_pipe").exists()

    /** A system property, or "" when it is missing or can't be read. */
    private fun prop(name: String): String = try {
        val get = Class.forName("android.os.SystemProperties")
            .getMethod("get", String::class.java)
        (get.invoke(null, name) as? String).orEmpty()
    } catch (t: Throwable) {
        try {
            val p = ProcessBuilder("getprop", name).start()
            val value = p.inputStream.bufferedReader().readText().trim()
            p.destroy()
            value
        } catch (t2: Throwable) {
            ""
        }
    }

    /**
     * GL_RENDERER from a throwaway 1x1 context on a thread of its own,
     * given 2 s: the same name the Vulkan driver reports for Adreno,
     * PowerVR and Maleoon. Null when it can't be read.
     */
    private fun glRenderer(): String? {
        var name: String? = null
        val probe = Thread({ name = try { readRenderer() } catch (t: Throwable) { null } }, "gpu-name")
        probe.start()
        probe.join(2000)
        return name
    }

    private fun readRenderer(): String? {
        val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (display == EGL14.EGL_NO_DISPLAY) return null
        val version = IntArray(2)
        if (!EGL14.eglInitialize(display, version, 0, version, 1)) return null
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        val wanted = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_NONE,
        )
        if (!EGL14.eglChooseConfig(display, wanted, 0, configs, 0, 1, count, 0) || count[0] == 0) {
            return null
        }
        val config = configs[0] ?: return null
        val context = EGL14.eglCreateContext(
            display, config, EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0,
        )
        if (context == EGL14.EGL_NO_CONTEXT) return null
        val surface = EGL14.eglCreatePbufferSurface(
            display, config, intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0,
        )
        try {
            if (surface == EGL14.EGL_NO_SURFACE) return null
            if (!EGL14.eglMakeCurrent(display, surface, surface, context)) return null
            return GLES20.glGetString(GLES20.GL_RENDERER)
        } finally {
            // The display stays initialized: Android's own renderer shares it.
            EGL14.eglMakeCurrent(
                display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT,
            )
            if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
            EGL14.eglDestroyContext(display, context)
        }
    }
}

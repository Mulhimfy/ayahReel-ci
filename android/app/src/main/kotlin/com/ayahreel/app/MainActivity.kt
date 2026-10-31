package com.ayahreel.app

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {

    /** The ayahreel/widget channel, once Dart is listening on it. */
    private var widgetChannel: MethodChannel? = null

    /**
     * A widget tap the app was opened with, held until Dart asks for it.
     * Cleared on hand-over, so a later hot restart does not replay it.
     */
    private var pendingLink: String? = null

    /** The pickAudio call waiting on the document picker. */
    private var pendingPick: MethodChannel.Result? = null

    /** Whether this activity's engine was asked for Skia (RenderBackend). */
    private var askedSkia = false

    /**
     * Skia instead of Impeller where Impeller would draw with OpenGL ES:
     * see RenderBackend. Read by the first engine start of the process.
     */
    @Suppress("DEPRECATION")
    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        val reason = RenderBackend.skiaReason(this)
        askedSkia = reason != null
        if (reason != null) {
            args.add(FlutterShellArgs.ARG_DISABLE_IMPELLER)
            Log.i("AyahReel", "drawing with Skia: $reason")
        }
        return args
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        if (!askedSkia) RenderBackend.learn(this)
    }

    /**
     * FFmpeg's native libraries, loaded on a thread of their own while
     * the engine starts.
     *
     * The FFmpeg plugin registers inside super.onCreate, on the main
     * thread and before Flutter's first frame, and its registration
     * touches FFmpegKitConfig, whose class initializer loads nine native
     * libraries (avcodec with x264 among them). Every launch, warm ones
     * too, held the launch screen for that. Started here, the load runs
     * on another core beside the engine's own start, and the plugin finds
     * the class ready, or waits only for what is left. Class
     * initialization is the JVM's to make safe: whichever thread comes
     * second waits for the first. Once per process.
     */
    private fun preloadFfmpeg() {
        if (ffmpegPreloaded) return
        ffmpegPreloaded = true
        Thread({
            try {
                Class.forName("com.antonkarpenko.ffmpegkit.FFmpegKitConfig")
            } catch (t: Throwable) {
                Log.w("AyahReel", "FFmpeg not preloaded", t)
            }
        }, "ffmpeg-preload").start()
    }

    /**
     * Back on the app's first screen sends the app behind, as Home does,
     * instead of finishing the activity.
     *
     * Flutter's default finishes it (FlutterActivity is no
     * OnBackPressedDispatcherOwner, so PlatformPlugin calls finish()),
     * and with it goes the engine: the next launch starts Dart, every
     * plugin and the first frame again in a process that is still
     * running. Play counts that as a warm start; 16.75% of them were
     * slow (over 2 s, P90 2.6 s; 28 days to 2026-10-28), against 11%
     * for similar apps. Android 12 and later already treat Back on a
     * launcher's root activity this way for apps that leave it to the
     * system. Only as the task's root: opened inside another app's
     * task, Back still returns to that app.
     */
    override fun popSystemNavigator(): Boolean = isTaskRoot && moveTaskToBack(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        preloadFfmpeg()
        super.onCreate(savedInstanceState)
        // Only a fresh launch carries a link. A recreated activity, or one
        // reopened from Recents, gets the intent it first launched with
        // again, and an old challenge link would open itself a second
        // time.
        val fromHistory =
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        pendingLink =
            if (savedInstanceState == null && !fromHistory) widgetLink(intent) else null
    }

    /**
     * The activity is singleTop, so a widget tap while the app is open
     * arrives here rather than as a second launch. Handed straight to
     * Dart if it is listening, kept for it otherwise.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = widgetLink(intent) ?: return
        val channel = widgetChannel
        if (channel != null) channel.invokeMethod("onLink", link) else pendingLink = link
    }

    /** The intent's data if it is one of our own links, else null. */
    private fun widgetLink(intent: Intent?): String? {
        val uri = intent?.data ?: return null
        return if (uri.scheme == "ayahreel") uri.toString() else null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // A save's encodes, in a process of their own: see RenderService.
        RenderClient.attach(this, MethodChannel(messenger, "ayahreel/render"))

        // The listening model (AyahReel Listen): see ListenBridge.
        ListenBridge(messenger)

        // The app's side of the home-screen widget; see
        // HomeWidgetService in Dart for what each call is for.
        widgetChannel = MethodChannel(messenger, "ayahreel/widget").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchLink" -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }
                    "isInstalled" -> result.success(VerseWidget.ids(this).isNotEmpty())
                    "canRequestPin" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            AppWidgetManager.getInstance(this).isRequestPinAppWidgetSupported
                    )
                    "requestPin" -> result.success(requestPinWidget())
                    else -> result.notImplemented()
                }
            }
        }

        // The "audio file" door on Android; see pickAudio.
        MethodChannel(messenger, "ayahreel/picker")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickAudio") {
                    result.notImplemented(); return@setMethodCallHandler
                }
                pickAudio(result)
            }

        MethodChannel(messenger, "ayahreel/whatsapp")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareVideo") {
                    result.notImplemented(); return@setMethodCallHandler
                }
                withSharedUri(call.argument<String>("path"), result) { uri ->
                    val text = call.argument<String>("text") ?: ""
                    // Regular WhatsApp first, WhatsApp Business second;
                    // false (fall back to the share sheet) if neither exists.
                    listOf("com.whatsapp", "com.whatsapp.w4b").any { pkg ->
                        try {
                            startActivity(Intent(Intent.ACTION_SEND).apply {
                                type = "video/mp4"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                if (text.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, text)
                                setPackage(pkg)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            })
                            true
                        } catch (_: ActivityNotFoundException) {
                            false
                        }
                    }
                }
            }

        // Straight into another app's composer with the reel: TikTok's
        // editor, YouTube's upload screen. An ACTION_SEND pinned to each
        // of the packages Dart lists, in turn, as a share sheet's row for
        // that app would send it; false when none of them takes it, and
        // Dart opens the share sheet instead.
        //
        // shareFiles is the same for a card, or a carousel of them: the
        // pictures to Instagram, TikTok, Facebook or WhatsApp, as one
        // ACTION_SEND or, for several, one ACTION_SEND_MULTIPLE.
        MethodChannel(messenger, "ayahreel/apps")
            .setMethodCallHandler { call, result ->
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                val text = call.argument<String>("text") ?: ""
                when (call.method) {
                    "shareVideo" -> {
                        val title = call.argument<String>("title") ?: ""
                        withSharedUri(call.argument<String>("path"), result) { uri ->
                            packages.any { pkg -> sendTo(pkg, uri, text, title) }
                        }
                    }
                    "shareFiles" -> {
                        val mime = call.argument<String>("mime") ?: PNG
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        withSharedUris(paths, result) { uris ->
                            packages.any { pkg -> sendFilesTo(pkg, uris, mime, text) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(messenger, "ayahreel/instagram")
            .setMethodCallHandler { call, result ->
                val appId = call.argument<String>("appId") ?: ""
                if (call.method == "shareStory") {
                    withSharedUri(call.argument<String>("path"), result) { uri ->
                        shareStory(uri, appId)
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "shareStoryVideo") {
                    withSharedUri(call.argument<String>("path"), result) { uri ->
                        shareStoryVideo(uri, appId)
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "shareReel") {
                    result.notImplemented(); return@setMethodCallHandler
                }
                withSharedUri(call.argument<String>("path"), result) { uri ->
                    // The read grant has to be explicit as well as flagged:
                    // Instagram is a separate app reading a uri our provider
                    // owns, and the flag alone only covers the component the
                    // intent that carries it resolves to.
                    grantUriPermission(IG_PACKAGE, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)

                    // Meta's Sharing to Reels intent. Instagram accepts it
                    // only from an app it can name — a *registered, Live*
                    // Meta app id — and answers anything else with its own
                    // "…doesn't support sharing to Instagram at this time"
                    // dialog, which resolves, launches, and looks to us
                    // exactly like success. So without an app id this is
                    // not attempted at all; the send below opens the same
                    // composer without asking Instagram who we are.
                    val toReel = if (appId.isEmpty()) null else Intent(IG_ADD_TO_REEL).apply {
                        setDataAndType(uri, MP4)
                        setPackage(IG_PACKAGE)
                        // The same id under all three names Meta's own
                        // samples have used for it over the years; an
                        // extra Instagram does not read costs nothing.
                        putExtra("source_application", appId)
                        putExtra("com.instagram.platform.extra.APPLICATION_ID", appId)
                        putExtra("com.instagram.sharedSticker.appId", appId)
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }

                    // Instagram's own share handler, addressed by class.
                    // This is the entry the OS share sheet's Instagram row
                    // goes to, reached without the sheet: a video handed to
                    // it lands in the reel composer — trimmer, audio,
                    // cover, Next — which is where a reel is made.
                    val toHandler = sendIntent(uri).apply {
                        setClassName(IG_PACKAGE, IG_SHARE_HANDLER)
                    }

                    // Same send, addressed to the package instead of the
                    // class, for a build of Instagram that has moved or
                    // renamed that activity.
                    val toApp = sendIntent(uri)

                    // First one Instagram actually has, and false only when
                    // it has none of them — then the share sheet is the
                    // right answer.
                    listOfNotNull(toReel, toHandler, toApp).any { intent -> launch(intent) }
                }
            }
    }

    /**
     * Opens the system document picker on audio, for a recitation the
     * user brings in themselves. The answer arrives in onActivityResult:
     * `{path, name}` of a copy in the cache, or null if they backed out.
     *
     * Not file_selector, which this door used to open. Its Android half
     * reads the whole picked file into a byte array and sends it across
     * the channel as well as copying it to disk — all on the main
     * thread. A 115 MB full-surah MP3 took the heap to 442 MB of 442 MB
     * and had the low-memory killer clearing every other app off the
     * phone; on a phone with a smaller heap that is an OutOfMemoryError
     * and the app is gone. Here the file is only ever streamed.
     */
    private fun pickAudio(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "a pick is already open", null)
            return
        }
        val filtered = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, AUDIO_TYPES)
        }
        // Some OEM builds have nothing that takes a filtered open-
        // document intent. Any file at all beats a dead button, and
        // ffprobe checks whatever arrives before it is trusted.
        val plain = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        pendingPick = result
        for (intent in listOf(filtered, plain)) {
            try {
                startActivityForResult(intent, PICK_AUDIO)
                return
            } catch (_: ActivityNotFoundException) {
            } catch (e: Exception) {
                // Anything else (a SecurityException on some OEM
                // builds) is answered here, and the pick let go: left
                // set, every later tap was refused as "busy" until the
                // activity was recreated.
                pendingPick = null
                result.error("no_picker", e.toString(), null)
                return
            }
        }
        pendingPick = null
        result.error("no_picker", "nothing on this phone opens documents", null)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_AUDIO) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // A full surah is a hundred megabytes on a slow phone's storage:
        // copied off the main thread, so the app stays responsive while
        // it happens.
        Thread {
            try {
                val (copy, name) = copyPicked(uri)
                runOnUiThread {
                    result.success(mapOf("path" to copy.path, "name" to name))
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("unreadable", e.message, null) }
            }
        }.start()
    }

    /**
     * Streams the picked document into the cache and returns the copy
     * and the name the user knows the file by.
     *
     * The copy is named `pick.<ext>` rather than after the file: the
     * import only needs the bytes, and a name off a chat app can carry
     * a quote that splits an FFmpeg command, or an emoji that does not
     * survive the trip into FFmpeg's C strings. Only the last pick is
     * kept, since the import converts it into the app's own storage and
     * never reads it again.
     */
    private fun copyPicked(uri: Uri): Pair<File, String> {
        var name: String? = null
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0) }
        val shown = name?.takeIf { it.isNotBlank() } ?: "audio"
        val ext = shown.substringAfterLast('.', "").lowercase()
            .takeIf { it.length in 1..5 && it.all(Char::isLetterOrDigit) }
            ?: contentResolver.getType(uri)
                ?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
        val dir = File(cacheDir, "picked_audio")
        dir.deleteRecursively()
        dir.mkdirs()
        val copy = File(dir, if (ext == null) "pick" else "pick.$ext")
        val input = contentResolver.openInputStream(uri)
            ?: throw IOException("no stream for $uri")
        input.use { from -> copy.outputStream().use { to -> from.copyTo(to, 1 shl 16) } }
        if (copy.length() == 0L) throw IOException("empty file")
        return copy to shown
    }

    /**
     * Asks the launcher to place the verse widget. The launcher shows
     * its own confirmation; true means it was asked. Launchers without
     * the pin API (Android 7, some third-party ones) answer false and
     * the sheet in the app keeps its step-by-step instructions up.
     */
    private fun requestPinWidget(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = AppWidgetManager.getInstance(this)
        if (!manager.isRequestPinAppWidgetSupported) return false
        return try {
            manager.requestPinAppWidget(VerseWidget.component(this), null, null)
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Meta's "Sharing to Stories" hand-off: opens Instagram's story
     * composer with the picture at [uri] laid over the whole story as
     * its background. Unlike the reel action, Instagram opens this one
     * without a registered app id — the id, when there is one, is what
     * puts the "from AyahReel" attribution on the story.
     *
     * Falls back to a plain send addressed to Instagram, whose own
     * share handler offers Story among its destinations, and answers
     * false only when Instagram has neither — then the share sheet is
     * the right answer.
     */
    private fun shareStory(uri: Uri, appId: String): Boolean {
        grantUriPermission(IG_PACKAGE, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val toStory = Intent(IG_ADD_TO_STORY).apply {
            setDataAndType(uri, PNG)
            setPackage(IG_PACKAGE)
            if (appId.isNotEmpty()) putExtra("source_application", appId)
            clipData = ClipData.newRawUri("story", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val toApp = sendIntent(uri, PNG)
        return listOf(toStory, toApp).any { intent -> launch(intent) }
    }

    /**
     * A finished reel into Instagram's *story* composer rather than its
     * reel one.
     *
     * Instagram's own Stories share target leads: it is where the share
     * sheet's "Stories" row goes, and it takes a video of any length,
     * cutting a long one into story-length parts the way it does from
     * the gallery. Meta's ADD_TO_STORY hand-off comes second — it opens
     * the same composer, but its background video is documented as a
     * short clip. No plain send after them: that lands in the reel
     * composer, which is the other button. False sends Dart to the
     * share sheet, whose Instagram rows include Stories.
     */
    private fun shareStoryVideo(uri: Uri, appId: String): Boolean {
        grantUriPermission(IG_PACKAGE, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val toStories = sendIntent(uri, MP4).apply {
            setClassName(IG_PACKAGE, IG_STORY_HANDLER)
        }
        val toStory = Intent(IG_ADD_TO_STORY).apply {
            setDataAndType(uri, MP4)
            setPackage(IG_PACKAGE)
            if (appId.isNotEmpty()) putExtra("source_application", appId)
            clipData = ClipData.newRawUri("story", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return listOf(toStories, toStory).any { intent -> launch(intent) }
    }

    /**
     * ACTION_SEND of the reel at [uri] to [pkg], with [text] and [title]
     * for an app that reads them; false when [pkg] isn't there to take
     * it. The read grant is explicit as well as flagged, as Instagram's
     * is: the receiver is a separate app reading a uri our provider owns.
     */
    private fun sendTo(pkg: String, uri: Uri, text: String, title: String): Boolean {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = MP4
            setPackage(pkg)
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("reel", uri)
            if (text.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, text)
            if (title.isNotEmpty()) {
                putExtra(Intent.EXTRA_TITLE, title)
                putExtra(Intent.EXTRA_SUBJECT, title)
            }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (packageManager.resolveActivity(intent, 0) == null) return false
        try {
            grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
            // The flag on the intent still carries the grant.
        }
        return launch(intent)
    }

    /**
     * The files at [uris], all of type [mime], to [pkg] with [text]: one
     * as an ACTION_SEND, several as an ACTION_SEND_MULTIPLE. False when
     * [pkg] isn't there to take them.
     */
    private fun sendFilesTo(pkg: String, uris: List<Uri>, mime: String, text: String): Boolean {
        if (uris.isEmpty()) return false
        val one = uris.size == 1
        val intent = Intent(if (one) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE)
        if (one) {
            intent.putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList<Uri>(uris))
        }
        intent.type = mime
        intent.setPackage(pkg)
        val clip = ClipData.newRawUri("files", uris[0])
        for (i in 1 until uris.size) clip.addItem(ClipData.Item(uris[i]))
        intent.clipData = clip
        if (text.isNotEmpty()) intent.putExtra(Intent.EXTRA_TEXT, text)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (packageManager.resolveActivity(intent, 0) == null) return false
        for (uri in uris) {
            try {
                grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: Exception) {
                // The flag on the intent still carries the grant.
            }
        }
        return launch(intent)
    }

    /** ACTION_SEND of [uri] as [mime], pinned to Instagram. */
    private fun sendIntent(uri: Uri, mime: String = MP4) = Intent(Intent.ACTION_SEND).apply {
        type = mime
        setPackage(IG_PACKAGE)
        putExtra(Intent.EXTRA_STREAM, uri)
        // ClipData as well as the extra: some readers take the grant off
        // the clip data alone, and an intent addressed by class carries
        // no grant at all without it.
        clipData = ClipData.newRawUri("reel", uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    /**
     * Starts [intent] if something is there to receive it.
     *
     * Resolving first is the point: startActivity alone only tells us
     * about a *missing* app, and every fallback below the first one
     * exists for an Instagram that is installed but does not have that
     * particular entry point.
     */
    private fun launch(intent: Intent): Boolean {
        if (packageManager.resolveActivity(intent, 0) == null) return false
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    /**
     * Turns the staged path Dart handed us into a uri the target app can
     * read, then runs [hand] with it. Errors go back as channel errors;
     * [hand]'s own answer is whether the app took the video.
     */
    private fun withSharedUri(
        path: String?,
        result: MethodChannel.Result,
        hand: (Uri) -> Boolean,
    ) {
        if (path == null) {
            result.error("bad_args", "path is required", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("not_found", "no file at $path", null)
            return
        }
        try {
            // Dart stages the file into the cache dir, which is the
            // only root this provider exposes (see ayahreel_file_paths).
            val uri = FileProvider.getUriForFile(
                this, "$packageName.ayahreel.fileprovider", file
            )
            result.success(hand(uri))
        } catch (e: Exception) {
            result.error("share_failed", e.message, null)
        }
    }

    /**
     * [withSharedUri] for several files: every one must be there, and
     * [hand] gets them in the order Dart gave them.
     */
    private fun withSharedUris(
        paths: List<String>,
        result: MethodChannel.Result,
        hand: (List<Uri>) -> Boolean,
    ) {
        if (paths.isEmpty()) {
            result.error("bad_args", "paths are required", null)
            return
        }
        try {
            val uris = paths.map { path ->
                val file = File(path)
                if (!file.exists()) {
                    result.error("not_found", "no file at $path", null)
                    return
                }
                FileProvider.getUriForFile(this, "$packageName.ayahreel.fileprovider", file)
            }
            result.success(hand(uris))
        } catch (e: Exception) {
            result.error("share_failed", e.message, null)
        }
    }

    private companion object {
        /** See preloadFfmpeg: once per process, whatever recreates the activity. */
        @Volatile
        var ffmpegPreloaded = false

        /** Request code for pickAudio; clear of every plugin's own. */
        const val PICK_AUDIO = 7301

        /** What the audio door lists: every audio type, the .mp4 an
         *  audio-only export often arrives in, and Ogg as some
         *  providers still label it. */
        val AUDIO_TYPES = arrayOf("audio/*", "video/mp4", "application/ogg")

        const val MP4 = "video/mp4"
        const val PNG = "image/png"
        const val IG_PACKAGE = "com.instagram.android"
        const val IG_ADD_TO_REEL = "com.instagram.share.ADD_TO_REEL"
        const val IG_ADD_TO_STORY = "com.instagram.share.ADD_TO_STORY"

        /** Instagram's share entry point — where the share sheet's own
         *  Instagram row leads, and the reel composer behind it. */
        const val IG_SHARE_HANDLER =
            "com.instagram.share.handleractivity.ShareHandlerActivity"

        /** The share sheet's "Stories" row: the story composer. */
        const val IG_STORY_HANDLER =
            "com.instagram.share.handleractivity.StoryShareHandlerActivity"
    }
}

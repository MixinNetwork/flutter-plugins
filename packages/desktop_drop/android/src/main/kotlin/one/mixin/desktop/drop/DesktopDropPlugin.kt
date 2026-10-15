package one.mixin.desktop.drop

import android.app.Activity
import android.content.ClipDescription
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.view.DragEvent
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class DesktopDropPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var dragView: FlutterView? = null
    private var session = 0L
    private var request = 0L
    private var generation = 0L
    private var revision = 0L
    private var inside = false
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    private fun preview(description: ClipDescription?): Map<String, Any?> {
        val types = mutableSetOf<String>()
        if (description?.hasMimeType("text/plain") == true) types.add("text")
        if (description?.hasMimeType("text/uri-list") == true) types.add("url")
        // A content URI can advertise text/plain or text/uri-list too. Until
        // ACTION_DROP exposes ClipData, keep file acceptance tentative.
        if (description != null && description.mimeTypeCount > 0) types.add("file")
        return mapOf("types" to types.toList(), "files" to emptyList<Any>(),
            "urls" to emptyList<String>(), "isComplete" to false)
    }

    private fun args(event: DragEvent, offer: Map<String, Any?>, final: Boolean): Map<String, Any?> {
        val density = dragView?.resources?.displayMetrics?.density ?: 1f
        return mapOf("view" to 0L, "generation" to generation, "session" to session,
            "request" to ++request, "phase" to if (final) 2 else 1,
            "x" to event.x.toDouble() / density, "y" to event.y.toDouble() / density,
            "offer" to offer)
    }

    private fun query(args: Map<String, Any?>, done: (Long) -> Unit) {
        val current = channel ?: return done(0)
        var finished = false
        val timeout = Runnable { if (!finished) { finished = true; done(0) } }
        main.postDelayed(timeout, 100)
        current.invokeMethod("query", args, object : MethodChannel.Result {
            private fun finish(target: Long) {
                if (finished) return
                finished = true
                main.removeCallbacks(timeout)
                done(target)
            }
            override fun success(result: Any?) = finish((result as? Number)?.toLong() ?: 0)
            override fun error(code: String, message: String?, details: Any?) = finish(0)
            override fun notImplemented() = finish(0)
        })
    }

    private val listener = View.OnDragListener { _, event ->
        when (event.action) {
            DragEvent.ACTION_DRAG_STARTED -> { session++; revision++; inside = true; true }
            DragEvent.ACTION_DRAG_ENTERED, DragEvent.ACTION_DRAG_LOCATION -> {
                inside = true
                val serial = ++revision
                val args = args(event, preview(event.clipDescription), false)
                query(args) { target ->
                    if (inside && revision == serial) channel?.invokeMethod("feedback", args + ("target" to target))
                }
                true
            }
            DragEvent.ACTION_DRAG_EXITED, DragEvent.ACTION_DRAG_ENDED -> {
                inside = false; revision++
                channel?.invokeMethod("exit", mapOf("view" to 0L, "generation" to generation, "session" to session))
                true
            }
            DragEvent.ACTION_DROP -> { drop(event); true }
            else -> false
        }
    }

    private fun drop(event: DragEvent) {
        val host = activity ?: return
        val data = event.clipData ?: return
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
            host.requestDragAndDropPermissions(event) else null
        val files = mutableListOf<Map<String, Any?>>()
        val fileUris = mutableListOf<Uri>()
        val urls = mutableListOf<String>()
        val texts = mutableListOf<String>()
        for (i in 0 until data.itemCount) {
            val item = data.getItemAt(i)
            item.text?.let { texts.add(it.toString()) }
            item.uri?.let { uri ->
                if (uri.scheme == "content" || uri.scheme == "file") {
                    fileUris.add(uri)
                    var name = uri.lastPathSegment ?: "drop"
                    if (uri.scheme == "content") {
                        try {
                            host.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                                if (cursor.moveToFirst()) name = cursor.getString(0) ?: name
                            }
                        } catch (_: Exception) { }
                    }
                    files.add(mapOf("name" to name, "mimeType" to runCatching { host.contentResolver.getType(uri) }.getOrNull()))
                } else urls.add(uri.toString())
            }
        }
        val offer = mapOf("types" to listOfNotNull(if (files.isNotEmpty()) "file" else null,
            if (texts.isNotEmpty()) "text" else null, if (urls.isNotEmpty()) "url" else null),
            "files" to files, "urls" to urls, "text" to texts.takeIf { it.isNotEmpty() }?.joinToString("\n"), "isComplete" to true)
        val args = args(event, offer, true)
        val epoch = generation
        query(args) { target ->
            if (epoch != generation || channel == null || activity !== host) { permission?.release(); return@query }
            channel?.invokeMethod("feedback", args + ("target" to target))
            if (target <= 0) { permission?.release(); return@query }
            // Android grants URI access only for this drag. Materialize while
            // the permission is held so DropItem remains readable after drop.
            io.execute {
                val materialized = mutableListOf<Map<String, Any?>>()
                val directories = mutableListOf<File>()
                fun discard() { directories.forEach { it.deleteRecursively() } }
                try {
                    for ((index, uri) in fileUris.withIndex()) {
                        val directory = File(host.cacheDir, "desktop_drop/${java.util.UUID.randomUUID()}")
                        check(directory.mkdirs())
                        directories.add(directory)
                        val destination = File(directory, File(files[index]["name"] as String).name)
                        host.contentResolver.openInputStream(uri)?.use { input ->
                            destination.outputStream().use { input.copyTo(it) }
                        } ?: error("Cannot read dropped URI")
                        materialized.add(files[index] + ("path" to destination.path))
                    }
                    if (!main.post {
                        val current = channel
                        if (epoch == generation && activity === host && current != null) {
                            current.invokeMethod("drop", args + mapOf("target" to target,
                                "offer" to (offer + ("files" to materialized))))
                        } else discard()
                    }) discard()
                } catch (error: Exception) {
                    discard()
                    android.util.Log.e("desktop_drop", "Cannot read dropped data", error)
                } finally { permission?.release() }
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "desktop_drop")
        channel?.setMethodCallHandler(this)
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "initialize") { result.notImplemented(); return }
        activity?.let { attachView(it) }
        if (call.argument<Number>("view")?.toLong() != 0L || dragView == null) {
            result.error("unsupported_view", "Flutter view is not attached", null); return
        }
        generation++; revision++; inside = false
        result.success(mapOf("view" to 0L, "generation" to generation))
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        generation++
        channel?.setMethodCallHandler(null); channel = null
        detach()
        io.shutdown()
    }
    private fun findView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) findView(view.getChildAt(i))?.let { return it }
        return null
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val host = binding.activity
        activity = host
        // FlutterActivity attaches plugins before creating its FlutterView.
        // Also rebind after Activity recreation when Dart stays connected.
        host.window.decorView.post { if (activity === host) attachView(host) }
    }
    private fun attachView(host: Activity) {
        val content = host.findViewById<View>(android.R.id.content) ?: return
        val view = findView(content) ?: return
        if (dragView === view) return
        dragView?.setOnDragListener(null)
        dragView = view
        view.setOnDragListener(listener)
    }
    private fun detach() {
        revision++; inside = false
        dragView?.setOnDragListener(null); dragView = null; activity = null
    }
    override fun onDetachedFromActivityForConfigChanges() = detach()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detach()
}

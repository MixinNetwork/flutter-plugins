package one.mixin.desktop.drop

import android.app.Activity
import android.content.ClipDescription
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import android.view.DragAndDropPermissions
import android.view.DragEvent
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import java.io.InputStream
import java.util.concurrent.Executors

class DesktopDropPlugin : FlutterPlugin, ActivityAware {
    private var transport: FfiTransport? = null
    private var activity: Activity? = null
    private var dragView: FlutterView? = null
    private var session = 0L
    private var request = 0L
    private var generation = 0L
    private var revision = 0L
    private var inside = false
    private var hoverOffer: Map<String, Any?>? = null
    private var offerSent = false
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private class Source(
        val uris: List<Uri>,
        val files: List<Map<String, Any?>>,
        val typed: List<Boolean>,
        val permission: DragAndDropPermissions?,
    ) {
        @Volatile var released = false
        val readers = mutableMapOf<Long, InputStream>() // IO executor only.
    }
    private val sources = mutableMapOf<Long, Source>()
    private var nextReader = 0L

    private fun preview(description: ClipDescription?): Map<String, Any?> {
        val strings = mutableListOf<Map<String, Any?>>()
        for (type in listOf("text/plain", "text/html", "text/uri-list")) {
            if (description?.hasMimeType(type) == true) strings.add(mapOf("mimeType" to type, "value" to null))
        }
        // Before ACTION_DROP, a MIME type can describe a content URI or text.
        val files = if (description != null && description.mimeTypeCount > 0)
            listOf(mapOf("name" to "")) else emptyList()
        return mapOf("files" to files, "strings" to strings,
            "isComplete" to false, "allowedOperations" to listOf("copy"))
    }

    private fun args(event: DragEvent, offer: Map<String, Any?>?, final: Boolean): Map<String, Any?> {
        val density = dragView?.resources?.displayMetrics?.density ?: 1f
        val args = mutableMapOf<String, Any?>("view" to 0L, "generation" to generation, "session" to session,
            "request" to ++request, "phase" to if (final) 2 else 1,
            "x" to event.x.toDouble() / density, "y" to event.y.toDouble() / density,
            "operationMask" to 1)
        if (offer != null) args["offer"] = offer
        return args
    }

    private fun query(args: Map<String, Any?>, done: (Long, Int) -> Unit) {
        val current = transport ?: return done(0, 0)
        var finished = false
        var nativeRequest = 0L
        val timeout = Runnable { if (!finished) { finished = true; current.cancel(nativeRequest); done(0, 0) } }
        main.postDelayed(timeout, 100)
        nativeRequest = current.invoke("query", args, object : FfiTransport.Result {
            private fun finish(target: Long, operation: Int) {
                if (finished) return
                finished = true
                main.removeCallbacks(timeout)
                val accepted = target > 0 && operation == 1
                done(if (accepted) target else 0, if (accepted) 1 else 0)
            }
            override fun success(result: Any?) {
                val selection = result as? Map<*, *>
                if (finished) return
                val target = (selection?.get("target") as? Number)?.toLong() ?: 0
                val currentSession = args["session"] == session && args["generation"] == generation
                val offer = hoverOffer
                if (target == -1L && args["offer"] == null && currentSession && offer != null) {
                    finished = true
                    main.removeCallbacks(timeout)
                    offerSent = false
                    query(args + mapOf("offer" to offer), done)
                    return
                }
                if (target >= 0 && selection != null && currentSession && offer != null && args["offer"] === offer) {
                    offerSent = true
                }
                finish(target, (selection?.get("operation") as? Number)?.toInt() ?: 0)
            }
            override fun error(code: String, message: String?, details: Any?) = finish(0, 0)
            override fun notImplemented() = finish(0, 0)
        })
    }

    private val listener = View.OnDragListener { _, event ->
        when (event.action) {
            DragEvent.ACTION_DRAG_STARTED -> {
                session++; revision++; inside = true
                hoverOffer = preview(event.clipDescription); offerSent = false
                true
            }
            DragEvent.ACTION_DRAG_ENTERED, DragEvent.ACTION_DRAG_LOCATION -> {
                inside = true
                val serial = ++revision
                val offer = hoverOffer ?: preview(event.clipDescription).also { hoverOffer = it }
                val args = args(event, if (offerSent) null else offer, false)
                query(args) { target, operation ->
                    if (inside && revision == serial) transport?.invoke("feedback", (args - "offer") + mapOf("target" to target, "operation" to operation))
                }
                true
            }
            DragEvent.ACTION_DRAG_EXITED, DragEvent.ACTION_DRAG_ENDED -> {
                inside = false; revision++
                transport?.invoke("exit", mapOf("view" to 0L, "generation" to generation, "session" to session))
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
        val strings = mutableListOf<Map<String, String>>()
        val typed = mutableListOf<Boolean>()
        for (i in 0 until data.itemCount) {
            val item = data.getItemAt(i)
            item.text?.let { strings.add(mapOf("mimeType" to "text/plain", "value" to it.toString())) }
            item.htmlText?.let { strings.add(mapOf("mimeType" to "text/html", "value" to it)) }
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
                    var mime = runCatching { host.contentResolver.getType(uri) }.getOrNull()
                    val virtual = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                        DocumentsContract.isDocumentUri(host, uri) && runCatching {
                            host.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_FLAGS), null, null, null)?.use { cursor ->
                                cursor.moveToFirst() && (cursor.getInt(0) and DocumentsContract.Document.FLAG_VIRTUAL_DOCUMENT) != 0
                            } ?: false
                        }.getOrDefault(false)
                    if (virtual) mime = runCatching { host.contentResolver.getStreamTypes(uri, "*/*")?.firstOrNull() }.getOrNull()
                    typed.add(virtual)
                    files.add(mapOf("name" to name, "mimeType" to mime, "source" to (fileUris.size - 1)))
                } else urls.add(uri.toString())
            }
        }
        if (urls.isNotEmpty()) strings.add(mapOf("mimeType" to "text/uri-list", "value" to urls.joinToString("\r\n")))
        val offer = mapOf("files" to files, "strings" to strings,
            "isComplete" to true, "allowedOperations" to listOf("copy"))
        val args = args(event, offer, true)
        val epoch = generation
        query(args) { target, operation ->
            if (epoch != generation || args["session"] != session || transport == null || activity !== host) { permission?.release(); return@query }
            transport?.invoke("feedback", (args - "offer") + mapOf("target" to target, "operation" to operation))
            if (target <= 0) { permission?.release(); return@query }
            val source = Source(fileUris.toList(), files.toList(), typed.toList(), permission)
            val serial = args["session"] as Long
            sources[serial] = source
            // Keep URI permissions until this application's callback completes.
            transport?.invoke("drop", args + mapOf("target" to target, "operation" to operation), object : FfiTransport.Result {
                private fun finish() {
                    if (sources[serial] === source) sources.remove(serial)
                    releaseSource(source)
                }
                override fun success(result: Any?) = finish()
                override fun error(code: String, message: String?, details: Any?) = finish()
                override fun notImplemented() = finish()
            })
        }
    }

    private fun releaseSource(source: Source) {
        if (source.released) return
        source.released = true
        source.permission?.release()
        if (!io.isShutdown) io.execute {
            source.readers.values.forEach { runCatching { it.close() } }
            source.readers.clear()
        }
    }

    private fun releaseSources() {
        sources.values.forEach { releaseSource(it) }
        sources.clear()
    }

    private fun readSource(call: MethodCall, result: FfiTransport.Result) {
        val op = call.argument<String>("op")
        val epoch = call.argument<Number>("generation")?.toLong()
        val serial = call.argument<Number>("session")?.toLong()
        val source = sources[serial]
        val current = epoch == generation && source != null && !source.released
        val host = activity
        if (!current || source == null || host == null) {
            result.error("source_expired", "Dropped source is no longer available", null); return
        }
        val stream = call.argument<Number>("stream")?.toLong()
        val index = call.argument<Number>("source")?.toInt() ?: -1
        val uri = source.uris.getOrNull(index)
        val metadata = source.files.getOrNull(index)
        val virtual = source.typed.getOrNull(index) == true
        if (op == "stat") {
            if (metadata == null) result.error("source_expired", "Dropped item is no longer available", null)
            else result.success(mapOf("name" to metadata["name"]))
            return
        }
        io.execute {
            var opened: Long? = null
            try {
                val value: Any? = when (op) {
                    "open" -> {
                        check(uri != null) { "Dropped item is no longer available" }
                        val input = if (virtual) {
                            val mime = metadata?.get("mimeType") as? String ?: error("No byte representation for dropped document")
                            val descriptor = host.contentResolver.openTypedAssetFileDescriptor(uri, mime, null)
                                ?: error("Cannot open dropped document")
                            try { descriptor.createInputStream() }
                            catch (error: Exception) { descriptor.close(); throw error }
                        } else host.contentResolver.openInputStream(uri) ?: error("Cannot open dropped URI")
                        try {
                            var skip = call.argument<Number>("start")?.toLong() ?: 0L
                            require(skip >= 0)
                            while (skip > 0) {
                                val n = input.skip(skip)
                                if (n > 0) skip -= n
                                else if (input.read() < 0) break else skip--
                            }
                            val id = ++nextReader
                            source.readers[id] = input
                            opened = id
                            id
                        } catch (error: Exception) { input.close(); throw error }
                    }
                    "read" -> {
                        val input = source.readers[stream] ?: error("Dropped reader is no longer available")
                        val count = call.argument<Number>("count")?.toInt() ?: 65536
                        require(count in 1..65536)
                        val bytes = ByteArray(count)
                        val n = input.read(bytes)
                        if (n < 0) ByteArray(0) else bytes.copyOf(n)
                    }
                    "close" -> { source.readers.remove(stream)?.close(); null }
                    else -> error("Unknown dropped-source operation")
                }
                main.post {
                    if (epoch == generation && sources[serial] === source && !source.released && activity === host) result.success(value)
                    else {
                        opened?.let { id -> if (!io.isShutdown) io.execute { source.readers.remove(id)?.close() } }
                        result.error("source_expired", "Dropped source has expired", null)
                    }
                }
            } catch (error: Exception) {
                main.post { result.error("read_failed", error.message, null) }
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        transport = FfiTransport(binding.flutterEngine.engineId, ::handleCall)
    }
    private fun handleCall(call: MethodCall, result: FfiTransport.Result) {
        if (call.method == "readSource") { readSource(call, result); return }
        if (call.method != "initialize") { result.notImplemented(); return }
        activity?.let { attachView(it) }
        if (call.argument<Number>("view")?.toLong() != 0L || dragView == null) {
            result.error("unsupported_view", "Flutter view is not attached", null); return
        }
        releaseSources()
        generation++; revision++; inside = false
        hoverOffer = null; offerSent = false
        result.success(mapOf("view" to 0L, "generation" to generation))
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        releaseSources()
        generation++
        transport?.close(); transport = null
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
        releaseSources()
        revision++; inside = false
        hoverOffer = null; offerSent = false
        dragView?.setOnDragListener(null); dragView = null; activity = null
    }
    override fun onDetachedFromActivityForConfigChanges() = detach()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detach()
}

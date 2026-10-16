package one.mixin.desktop.drop

import android.app.Activity
import android.content.Intent
import android.content.ClipDescription
import android.database.Cursor
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
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.io.InputStream
import java.io.File
import java.util.concurrent.Executors

class DesktopDropPlugin : FlutterPlugin, ActivityAware {
    private var transport: FfiTransport? = null
    private var activity: Activity? = null
    private var dragView: FlutterView? = null
    private var session = 0L
    private val generation: Long get() = transport?.generation ?: 0L
    private var hoverOffer: Map<String, Any?>? = null
    private var offerSent = false
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private class Entry(var uri: Uri, val metadata: Map<String, Any?>, val typed: Boolean = false)
    private class Source(val entries: MutableList<Entry>, val permission: DragAndDropPermissions?) {
        @Volatile var released = false
        // Entries, URI indices, and readers belong to the IO executor after delivery.
        val readers = mutableMapOf<Long, InputStream>()
        private val indices = entries.withIndex().associate { it.value.uri to it.index }.toMutableMap()
        fun add(entry: Entry): Int = indices.getOrPut(entry.uri) {
            entries.add(entry)
            entries.lastIndex
        }
    }
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingAccess: ((Int, Intent?) -> Unit)? = null
    private var accessSource: Source? = null
    private val directoryRequestCode = 0xDD01
    private val accessListener = ActivityResultListener { request, result, data ->
        if (request != directoryRequestCode || pendingAccess == null) false else {
            val callback = pendingAccess
            pendingAccess = null
            accessSource = null
            callback?.invoke(result, data)
            true
        }
    }

    private fun requestDirectoryAccess(result: FfiTransport.Result, source: Source, parent: Entry) {
        val host = activity
        if (host == null || source.released) {
            result.error("source_expired", "Dropped source has expired", null); return
        }
        if (pendingAccess != null) {
            result.error("directory_access_denied", "Directory access was not granted", null); return
        }
        val original = parent.uri
        accessSource = source
        pendingAccess = { code, data ->
            val tree = data?.data
            if (source.released) result.error("source_expired", "Dropped source has expired", null)
            else if (code != Activity.RESULT_OK || tree == null) {
                result.error("directory_access_denied", "Directory access was cancelled", null)
            } else if (tree.authority != original.authority) {
                result.error("directory_access_denied", "Select the directory that was dropped", null)
            } else {
                // Keep the dropped document ID: providers may use different IDs
                // for the same folder in drag data and tree grants. The provider
                // enforces that the original document belongs to the granted tree.
                parent.uri = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getDocumentId(original))
                result.success(null)
            }
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, original)
        }
        try { host.startActivityForResult(intent, directoryRequestCode) }
        catch (error: Exception) {
            pendingAccess = null; accessSource = null
            result.error("directory_access_denied", error.message, null)
        }
    }

    private val sources = mutableMapOf<Long, Source>()
    private var nextReader = 0L

    private fun preview(description: ClipDescription?): Map<String, Any?> {
        val strings = mutableListOf<Map<String, Any?>>()
        for (type in listOf("text/plain", "text/html", "text/uri-list")) {
            if (description?.hasMimeType(type) == true) strings.add(mapOf("mimeType" to type, "value" to null))
        }
        // A MIME type can describe either a URI file or a string. Preserve the
        // advertised formats as tentative representations until ACTION_DROP.
        val files = (0 until (description?.mimeTypeCount ?: 0)).map { index ->
            val mime = description!!.getMimeType(index)
            mapOf("name" to "", "mimeType" to mime,
                "isDirectory" to (mime == DocumentsContract.Document.MIME_TYPE_DIR))
        }
        return mapOf("files" to files, "strings" to strings,
            "isComplete" to false, "allowedOperations" to listOf("copy"))
    }

    private val documentColumns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE,
        DocumentsContract.Document.COLUMN_FLAGS, DocumentsContract.Document.COLUMN_SIZE)

    private fun contentEntry(host: Activity, uri: Uri, cursor: Cursor?): Entry {
        fun text(column: String): String? {
            val index = cursor?.getColumnIndex(column) ?: -1
            return if (index >= 0 && !cursor!!.isNull(index)) cursor.getString(index) else null
        }
        val name = text(OpenableColumns.DISPLAY_NAME) ?: uri.lastPathSegment ?: "drop"
        var mime = text(DocumentsContract.Document.COLUMN_MIME_TYPE)
            ?: runCatching { host.contentResolver.getType(uri) }.getOrNull()
        val directory = mime == DocumentsContract.Document.MIME_TYPE_DIR
        val flags = text(DocumentsContract.Document.COLUMN_FLAGS)?.toIntOrNull() ?: 0
        val virtual = !directory && (flags and DocumentsContract.Document.FLAG_VIRTUAL_DOCUMENT) != 0
        if (virtual) mime = host.contentResolver.getStreamTypes(uri, "*/*")?.firstOrNull()
        return Entry(uri, mapOf("name" to name, "mimeType" to mime, "isDirectory" to directory,
            "length" to text(OpenableColumns.SIZE)?.toLongOrNull()), virtual)
    }

    private fun entry(host: Activity, sourceUri: Uri): Entry {
        val uri = if (sourceUri.scheme == "content" && DocumentsContract.isTreeUri(sourceUri) &&
            !DocumentsContract.isDocumentUri(host, sourceUri)) {
            DocumentsContract.buildDocumentUriUsingTree(sourceUri, DocumentsContract.getTreeDocumentId(sourceUri))
        } else sourceUri
        if (uri.scheme == "file") {
            val file = File(uri.path ?: error("Missing dropped file path"))
            return Entry(uri, mapOf("name" to file.name, "isDirectory" to file.isDirectory,
                "length" to file.length()))
        }
        val columns = if (DocumentsContract.isDocumentUri(host, uri)) documentColumns
            else arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return try {
            host.contentResolver.query(uri, columns, null, null, null).use { cursor ->
                contentEntry(host, uri, cursor?.takeIf { it.moveToFirst() })
            }
        } catch (_: Exception) {
            // Some providers expose only the type until their data is opened.
            contentEntry(host, uri, null)
        }
    }

    private fun listDirectory(host: Activity, source: Source, parent: Entry): List<Map<String, Any?>> {
        check(parent.metadata["isDirectory"] == true) { "Dropped item is not a directory" }
        val children = mutableListOf<Map<String, Any?>>()
        fun add(child: Entry) { children.add(child.metadata + mapOf("source" to source.add(child))) }
        val uri = parent.uri
        if (uri.scheme == "file") {
            val files = File(uri.path!!).listFiles() ?: error("Cannot list dropped directory")
            files.forEach { add(entry(host, Uri.fromFile(it))) }
        } else {
            val id = DocumentsContract.getDocumentId(uri)
            val tree = DocumentsContract.isTreeUri(uri)
            val childUri = if (tree) DocumentsContract.buildChildDocumentsUriUsingTree(uri, id)
                else DocumentsContract.buildChildDocumentsUri(uri.authority!!, id)
            val cursor = host.contentResolver.query(childUri, documentColumns, null, null, null)
                ?: error("Provider did not return directory entries")
            cursor.use {
                val idColumn = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                while (it.moveToNext()) {
                    val childId = it.getString(idColumn)
                    val child = if (tree) DocumentsContract.buildDocumentUriUsingTree(uri, childId)
                        else DocumentsContract.buildDocumentUri(uri.authority!!, childId)
                    add(contentEntry(host, child, it))
                }
            }
        }
        return children
    }

    private fun choose(event: DragEvent, offer: Map<String, Any?>, phase: Int): Map<String, Any?> {
        val current = transport ?: return mapOf("target" to 0L, "operation" to 0)
        val density = dragView?.resources?.displayMetrics?.density ?: 1f
        val x = event.x.toDouble() / density
        val y = event.y.toDouble() / density
        fun request(full: Boolean): FfiTransport.Decision {
            val payload = mutableMapOf<String, Any?>("operationMask" to 1)
            if (full) payload["offer"] = offer
            return current.decide(session, phase, x, y, payload)
        }
        var decision = request(phase != 1 || !offerSent)
        if (decision.target == -1L) decision = request(true)
        offerSent = true
        val accepted = decision.target > 0 && decision.operation == 1 && decision.generation == current.generation
        val args = mapOf("view" to 0L, "generation" to decision.generation, "session" to session,
            "request" to decision.request, "phase" to phase,
            "x" to x, "y" to y, "operationMask" to 1,
            "target" to if (accepted) decision.target else 0L, "operation" to if (accepted) 1 else 0)
        current.invoke("feedback", args)
        return args
    }

    private val listener = View.OnDragListener { _, event ->
        when (event.action) {
            DragEvent.ACTION_DRAG_STARTED -> {
                session++
                hoverOffer = preview(event.clipDescription); offerSent = false
                // Subscribe to the drag. Acceptance is decided at its location,
                // and ACTION_DROP returns the final synchronous Dart decision.
                generation != 0L
            }
            DragEvent.ACTION_DRAG_ENTERED, DragEvent.ACTION_DRAG_LOCATION -> {
                val offer = hoverOffer ?: preview(event.clipDescription).also { hoverOffer = it }
                choose(event, offer, if (event.action == DragEvent.ACTION_DRAG_ENTERED) 0 else 1)
                true
            }
            DragEvent.ACTION_DRAG_EXITED, DragEvent.ACTION_DRAG_ENDED -> {
                transport?.invoke("exit", mapOf("view" to 0L, "generation" to generation, "session" to session))
                true
            }
            DragEvent.ACTION_DROP -> drop(event)
            else -> false
        }
    }

    private fun drop(event: DragEvent): Boolean {
        val host = activity ?: return false
        val data = event.clipData ?: return false
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
            host.requestDragAndDropPermissions(event) else null
        val files = mutableListOf<Map<String, Any?>>()
        val entries = mutableListOf<Entry>()
        val urls = mutableListOf<String>()
        val strings = mutableListOf<Map<String, String>>()
        for (i in 0 until data.itemCount) {
            val item = data.getItemAt(i)
            item.text?.let { strings.add(mapOf("mimeType" to "text/plain", "value" to it.toString())) }
            item.htmlText?.let { strings.add(mapOf("mimeType" to "text/html", "value" to it)) }
            item.uri?.let { uri ->
                if (uri.scheme == "content" || uri.scheme == "file") {
                    val item = entry(host, uri)
                    files.add(item.metadata + mapOf("source" to entries.size))
                    entries.add(item)
                } else urls.add(uri.toString())
            }
        }
        if (urls.isNotEmpty()) strings.add(mapOf("mimeType" to "text/uri-list", "value" to urls.joinToString("\r\n")))
        val offer = mapOf("files" to files, "strings" to strings,
            "isComplete" to true, "allowedOperations" to listOf("copy"))
        val current = transport
        if (current == null) { permission?.release(); return false }
        val args = choose(event, offer, 2)
        val target = args["target"] as Long
        if (target <= 0) { permission?.release(); return false }
        val source = Source(entries, permission)
        val serial = args["session"] as Long
        sources[serial] = source
        // Keep URI permissions until this application's callback completes.
        current.invoke("drop", args + mapOf("offer" to offer), object : FfiTransport.Result {
            private fun finish() {
                if (sources[serial] === source) sources.remove(serial)
                releaseSource(source)
            }
            override fun success(result: Any?) = finish()
            override fun error(code: String, message: String?, details: Any?) = finish()
            override fun notImplemented() = finish()
        })
        return true
    }

    private fun releaseSource(source: Source) {
        if (source.released) return
        source.released = true
        if (accessSource === source) {
            val callback = pendingAccess
            pendingAccess = null; accessSource = null
            callback?.invoke(Activity.RESULT_CANCELED, null)
        }
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
        if (op == "requestAccess") {
            // UI is requested only through the explicit public operation.
            io.execute {
                val parent = source.entries.getOrNull(index)
                main.post {
                    if (epoch != generation || sources[serial] !== source || source.released) {
                        result.error("source_expired", "Dropped source has expired", null)
                    } else if (parent == null || parent.metadata["isDirectory"] != true ||
                        !DocumentsContract.isDocumentUri(host, parent.uri)) {
                        result.error("unsupported_directory", "Directory does not support document-tree access", null)
                    } else requestDirectoryAccess(result, source, parent)
                }
            }
            return
        }
        io.execute {
            var opened: Long? = null
            try {
                check(!source.released) { "Dropped source has expired" }
                val item = source.entries.getOrNull(index)
                val uri = item?.uri
                val metadata = item?.metadata
                val value: Any? = when (op) {
                    "stat" -> metadata ?: error("Dropped item is no longer available")
                    "list" -> listDirectory(host, source, item ?: error("Dropped directory is no longer available"))
                    "open" -> {
                        check(item != null && uri != null) { "Dropped item is no longer available" }
                        check(metadata?.get("isDirectory") != true) { "Cannot open a directory as a file" }
                        val input = if (item.typed) {
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
            } catch (error: SecurityException) {
                main.post {
                    result.error(if (op == "list") "directory_access_required" else "read_access_denied",
                        if (op == "list") "Access to this directory's children was not granted. Request directory access explicitly before retrying."
                        else error.message, null)
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
        hoverOffer = null; offerSent = false
        result.success(mapOf("view" to 0L, "context" to transport!!.decisionContext))
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        releaseSources()
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
        activityBinding = binding
        binding.addActivityResultListener(accessListener)
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
        activityBinding?.removeActivityResultListener(accessListener)
        activityBinding = null
        hoverOffer = null; offerSent = false
        dragView?.setOnDragListener(null); dragView = null; activity = null
    }
    override fun onDetachedFromActivityForConfigChanges() = detach()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detach()
}

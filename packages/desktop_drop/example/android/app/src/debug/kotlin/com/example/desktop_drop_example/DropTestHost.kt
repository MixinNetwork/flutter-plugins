package com.example.desktop_drop_example

import android.content.ClipData
import android.provider.DocumentsContract
import android.os.Build
import android.os.Parcel
import android.view.DragEvent
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Example-only fixture exercising the real listener and JNI/Dart decision. */
object DropTestHost {
    @JvmStatic
    fun register(activity: FlutterActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "desktop_drop_example/test")
            .setMethodCallHandler { call, result ->
                if (call.method != "dispatchDrag") { result.notImplemented(); return@setMethodCallHandler }
                val view = findView(activity.window.decorView)
                if (view == null) { result.error("missing_view", "FlutterView is not attached", null); return@setMethodCallHandler }
                // This fixture follows DragEvent's parcel layout on API 31-37.
                if (Build.VERSION.SDK_INT !in 31..37) {
                    result.error("unsupported_sdk", "Drag fixture requires API 31-37", null)
                    return@setMethodCallHandler
                }
                val action = call.argument<Int>("action")!!
                val kind = call.argument<String>("kind") ?: "text"
                val data = if (kind == "text") ClipData.newPlainText("test", call.argument<String>("text") ?: "hello")
                else {
                    val name = when (kind) { "directory" -> "folder"; "image" -> "sample.png"; else -> "notes.txt" }
                    val authority = "${activity.packageName}.drop_test"
                    if (kind == "tree") ClipData("test", arrayOf(DocumentsContract.Document.MIME_TYPE_DIR),
                        ClipData.Item(DocumentsContract.buildTreeDocumentUri(authority, "folder")))
                    else ClipData.newUri(activity.contentResolver, "test", DocumentsContract.buildDocumentUri(authority, name))
                }
                val density = view.resources.displayMetrics.density
                val parcel = Parcel.obtain()
                try {
                    parcel.writeInt(action)
                    parcel.writeFloat(call.argument<Double>("x")!!.toFloat() * density)
                    parcel.writeFloat(call.argument<Double>("y")!!.toFloat() * density)
                    parcel.writeFloat(0f) // Shadow offsets.
                    parcel.writeFloat(0f)
                    if (Build.VERSION.SDK_INT >= 37 || (Build.VERSION.SDK_INT >= 36 && Build.MODEL.contains("Cuttlefish"))) parcel.writeInt(view.display?.displayId ?: 0)
                    if (Build.VERSION.SDK_INT >= 35) parcel.writeInt(0) // Flags.
                    if (Build.VERSION.SDK_INT >= 37) {
                        parcel.writeInt(0) // Input source.
                        parcel.writeInt(0) // Meta state.
                    }
                    parcel.writeInt(0) // Drag result.
                    parcel.writeInt(if (action == DragEvent.ACTION_DROP) 1 else 0)
                    if (action == DragEvent.ACTION_DROP) data.writeToParcel(parcel, 0)
                    parcel.writeInt(1)
                    data.description.writeToParcel(parcel, 0)
                    parcel.writeInt(0) // No drag surface or URI permission binder.
                    parcel.writeInt(0)
                    parcel.setDataPosition(0)
                    val event = DragEvent.CREATOR.createFromParcel(parcel)
                    result.success(view.dispatchDragEvent(event))
                } catch (error: Exception) {
                    result.error("dispatch_failed", error.message, null)
                } finally {
                    parcel.recycle()
                }
            }
    }

    private fun findView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) findView(view.getChildAt(i))?.let { return it }
        return null
    }
}

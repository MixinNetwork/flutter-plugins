package one.mixin.pasteboard

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.FileReader

/** PasteboardPlugin */
class PasteboardPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        private const val TAG = "PasteboardPlugin"


        // check mine-type is image
        private fun isImage(mimeType: String?): Boolean {
            return mimeType?.startsWith("image/") ?: false
        }

    }

    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pasteboard")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val contentResolver = context.contentResolver

        if (call.method == "image") {
            val primaryClip = clipboardManager.primaryClip
            if (primaryClip == null || primaryClip.itemCount == 0) {
                result.success(null)
                return
            }
            val item = primaryClip.getItemAt(0)
            val type = contentResolver.getType(item.uri)

            if (!isImage(type)) {
                result.success(null)
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                contentResolver.takePersistableUriPermission(item.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            val bytes = contentResolver.openInputStream(item.uri)?.use {
                it.readBytes()
            }
            result.success(bytes)
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}

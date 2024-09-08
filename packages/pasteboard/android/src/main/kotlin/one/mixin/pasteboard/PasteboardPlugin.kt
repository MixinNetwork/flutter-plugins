package one.mixin.pasteboard


import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID
import kotlin.concurrent.thread


/** PasteboardPlugin */
class PasteboardPlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var context: Context
  private lateinit var channel : MethodChannel

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pasteboard")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    val manager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val cr = context.contentResolver
    val first = manager.primaryClip?.getItemAt(0)
    when (call.method) {
      "image" -> {
        first?.uri?.let {
          val mime = cr.getType(it)
          if (mime == null || !mime.startsWith("image")) return result.success(null)
          result.success(cr.openInputStream(it).use { stream ->
            stream?.buffered()?.readBytes()
          })
        }
        result.success(null)
      }
      "files" -> {
        manager.primaryClip?.run {
          val files: MutableList<String> = mutableListOf()
          var finish = 0
          for (i in 0 until itemCount) {
            val name = UUID.randomUUID().toString()
            val file = File(context.cacheDir, name)
            getItemAt(i).uri?.let {
              // if copy big file, how to handle?
              thread {
                cr.openAssetFileDescriptor(it, "r")?.use { desc ->
                  FileInputStream(desc.fileDescriptor).use { inp ->
                    FileOutputStream(file).use { out ->
                      inp.copyTo(out)
                    }
                  }
                }
                if (++finish >= itemCount) {
                  result.success(files)
                }
              }
            }
            files.add(file.path.toString())
          } // need use toList?
        }
      }
      "html" -> result.success(first?.htmlText)
      "writeFiles" -> {
        val args = call.arguments<List<String>>() ?: return result.error(
          "NoArgs",
          "Missing Arguments",
          null,
        )
        val clip: ClipData? = null
        for (i in args) {
          val uri = Uri.parse(i)
          clip ?: ClipData.newUri(cr, "files", uri)
          clip?.addItem(ClipData.Item(uri))
        }
        clip?.let {
          manager.setPrimaryClip(it)
        }
        result.success(null)
      }
      "writeImage" -> {
        val image = call.arguments<ByteArray>() ?: return result.error(
          "NoArgs",
          "Missing Arguments",
          null,
        )
        val out = ByteArrayOutputStream()
        thread {
          val bitmap = BitmapFactory.decodeByteArray(image, 0, image.size)
          bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }
        val name = UUID.randomUUID().toString()
        val file = File(context.cacheDir, name)
        FileOutputStream(file).use {
          out.writeTo(it)
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.clipboard", file)
        val clip = ClipData.newUri(cr, "image.png", uri)
        manager.setPrimaryClip(clip)
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}

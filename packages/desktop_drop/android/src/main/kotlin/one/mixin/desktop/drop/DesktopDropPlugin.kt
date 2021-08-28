package one.mixin.desktop.drop

import android.app.Activity
import android.os.Build
import android.util.Log
import android.view.DragEvent
import android.view.View
import android.view.ViewGroup
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class DesktopDropPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    companion object {
        private const val TAG = "DesktopDropPlugin"
    }

    private var channel: MethodChannel? = null

    private var dragView: View? = null
    private var activity: Activity? = null

    private val dragListener = View.OnDragListener { _, event ->
        val channel = channel ?: return@OnDragListener false
        when (event.action) {
            DragEvent.ACTION_DRAG_ENTERED -> {
                channel.invokeMethod("entered", listOf(event.x, event.y))
            }
            DragEvent.ACTION_DRAG_LOCATION -> {
                channel.invokeMethod("updated", listOf(event.x, event.y))
            }
            DragEvent.ACTION_DRAG_EXITED -> {
                channel.invokeMethod("exited", null)
            }
            DragEvent.ACTION_DROP -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    handleDrop(event, channel, activity!!)
                }
            }
        }
        return@OnDragListener true
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun handleDrop(event: DragEvent, channel: MethodChannel, activity: Activity) {
        val permission = activity.requestDragAndDropPermissions(event) ?: return

        val result = mutableListOf<String>()
        for (i in 0 until event.clipData.itemCount) {
            event.clipData.getItemAt(i)?.uri?.let {
                result.add(it.toString())
            }
        }
        permission.release()

        channel.invokeMethod("performOperation", result)
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "desktop_drop")
        channel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        result.notImplemented()
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val content = binding.activity.findViewById<ViewGroup>(android.R.id.content)
        if (content == null) {
            Log.e(TAG, "onAttachedToActivity: can not find android.R.id.content")
            return
        }
        content.setOnDragListener(dragListener)
        dragView = content
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    }

    override fun onDetachedFromActivity() {
        dragView?.setOnDragListener(null)
        activity = null
    }
}


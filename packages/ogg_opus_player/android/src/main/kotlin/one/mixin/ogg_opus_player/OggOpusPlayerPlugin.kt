package one.mixin.ogg_opus_player

import android.content.Context
import android.os.SystemClock
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** OggOpusPlayerPlugin */
class OggOpusPlayerPlugin : FlutterPlugin, MethodCallHandler {

    companion object {

        private var lastGeneratedId = 0

        private fun generatePlayerId(): Int {
            lastGeneratedId++
            return lastGeneratedId
        }

    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    private val players = mutableMapOf<Int, AudioPlayer>()
    private val recorders = mutableMapOf<Int, OpusAudioRecorder>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ogg_opus_player")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "create" -> {
                val path = call.arguments as String
                val id = generatePlayerId()
                val player = AudioPlayer(context, path) {
                    handlePlayerStateChanged(id, it)
                }
                players[id] = player
                result.success(id)
            }
            "play" -> {
                (call.arguments as? Int)?.let {
                    players[it]?.play()
                }
                result.success(null)
            }
            "pause" -> {
                (call.arguments as? Int)?.let {
                    players[it]?.pause()
                }
                result.success(null)
            }
            "stop" -> {
                (call.arguments as? Int)?.let {
                    players[it]?.destroy()
                    players.remove(it)
                }
                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun handlePlayerStateChanged(id: Int, player: AudioPlayer) {
        channel.invokeMethod(
            "onPlayerStateChanged", mapOf(
                "state" to player.state.ordinal,
                "playerId" to id,
                "updateTime" to SystemClock.uptimeMillis(),
                "position" to player.position
            )
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}

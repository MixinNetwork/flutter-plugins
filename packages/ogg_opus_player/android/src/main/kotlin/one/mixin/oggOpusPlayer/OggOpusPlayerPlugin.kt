package one.mixin.oggOpusPlayer

import android.content.Context
import android.content.pm.PackageManager
import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

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

    @OptIn(UnstableApi::class)
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
            "setPlaybackSpeed" -> {
                val playerId = call.argument<Int>("playerId")
                val speed = call.argument<Double>("speed")
                val player = players[playerId]
                if (player != null && speed != null) {
                    player.playbackRate = speed
                    handlePlayerStateChanged(playerId!!, player)
                }
                result.success(null)
            }
            "createRecorder" -> {
                val path = call.arguments as String
                val id = generatePlayerId()
                val recorder =
                    OpusAudioRecorder(context, File(path), object : OpusAudioRecorder.Callback {
                        override fun onCancel() {
                            channel.invokeMethod(
                                "onRecorderCanceled", mapOf(
                                    "recorderId" to id,
                                    "reason" to 0,
                                )
                            )
                        }

                        override fun sendAudio(file: File, duration: Long, waveForm: ByteArray) {
                            channel.invokeMethod(
                                "onRecorderFinished", mapOf(
                                    "recorderId" to id,
                                    "duration" to duration,
                                    "waveform" to waveForm,
                                )
                            )
                        }
                    })
                recorders[id] = recorder
                result.success(id)
            }
            "startRecord" -> {
                // check has permission
                val hasPermission =
                    context.checkCallingOrSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                if (hasPermission == PackageManager.PERMISSION_DENIED) {
                    result.error("PERMISSION_DENIED", "RECORD_AUDIO", null)
                    return
                }
                (call.arguments as? Int)?.let {
                    recorders[it]?.startRecording()
                }
                result.success(null)
            }
            "stopRecord" -> {
                (call.arguments as? Int)?.let {
                    recorders[it]?.stopRecording(AudioEndStatus.SEND)
                }
                result.success(null)
            }
            "destroyRecorder" -> {
                (call.arguments as? Int)?.let {
                    recorders[it]?.stopRecording(AudioEndStatus.CANCEL)
                    recorders.remove(it)
                }
                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    @UnstableApi
    private fun handlePlayerStateChanged(id: Int, player: AudioPlayer) {
        channel.invokeMethod(
            "onPlayerStateChanged", mapOf(
                "state" to player.state.ordinal,
                "playerId" to id,
                "updateTime" to SystemClock.uptimeMillis(),
                "position" to player.position,
                "speed" to player.playbackRate,
            )
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}

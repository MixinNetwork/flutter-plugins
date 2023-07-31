package one.mixin.oggOpusPlayer

import android.content.Context
import android.util.Log
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.exoplayer2.upstream.DefaultDataSource

typealias OnPlayerStatusChangedCallback = (AudioPlayer) -> Unit

enum class Status {
    Stopped,
    Playing,
    Paused,
}

class AudioPlayer(
    context: Context,
    path: String,
    private val callback: OnPlayerStatusChangedCallback,
) : Player.Listener {

    companion object {
        private const val TAG = "AudioPlayer"
    }

    private val player = ExoPlayer.Builder(context)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build(),
            false
        )
        .setTrackSelector(DefaultTrackSelector(context)).build().apply {
            volume = 1.0f
        }

    val position: Double get() = player.currentPosition.toDouble() / 1000

    val state: Status
        get() {
            if (player.playbackState == Player.STATE_READY) {
                return if (player.playWhenReady) {
                    Status.Playing
                } else {
                    Status.Paused
                }
            } else if (player.playbackState == Player.STATE_ENDED) {
                return Status.Stopped
            }
            return Status.Paused
        }

    private var _playbackRate: Double = 1.0
    var playbackRate: Double
        set(value) {
            _playbackRate = value
            player.setPlaybackSpeed(value.toFloat())
        }
        get() = _playbackRate


    init {
        val mediaItem = MediaItem.fromUri(path)
        val datasource = ProgressiveMediaSource.Factory(DefaultDataSource.Factory(context))
            .createMediaSource(mediaItem)
        player.addListener(this)
        player.setMediaSource(datasource)
        player.prepare()
    }

    fun play() {
        player.playWhenReady = true
    }

    fun pause() {
        player.playWhenReady = false
    }

    fun destroy() {
        player.stop()
        player.removeListener(this)
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        Log.d(TAG, "onPlayWhenReadyChanged: $playWhenReady $reason")
        callback(this)
    }

    override fun onPlayerError(error: PlaybackException) {
        callback(this)
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        callback(this)
    }

}
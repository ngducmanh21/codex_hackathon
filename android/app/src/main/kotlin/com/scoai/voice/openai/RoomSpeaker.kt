package com.scoai.voice.openai

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRouting
import android.media.AudioTrack
import java.util.concurrent.LinkedBlockingQueue

/**
 * Plays "Phát biểu" speech on the phone's own loudspeaker, so the room hears
 * it even while the user wears headphones (the user's own read-aloud keeps
 * going to the headphones through the normal media route).
 *
 * The track asks Android for the built-in speaker as its preferred device.
 * If Android routes it elsewhere anyway, the next utterance uses the alarm
 * route, which Android plays on the loudspeaker even with headphones in.
 */
class RoomSpeaker(private val context: Context) {
    private val lock = Any()
    private var track: AudioTrack? = null
    private var rate = 0
    private var queue = LinkedBlockingQueue<ByteArray>()
    private var writer: Thread? = null
    private var route = "none"

    @Volatile
    private var useAlarmRoute = false

    /**
     * Queues 16-bit mono little-endian [pcm] at [sampleRate] and returns how
     * it is routed: "speaker", "alarm" or "default".
     */
    fun play(pcm: ByteArray, sampleRate: Int): String = synchronized(lock) {
        if (track == null || rate != sampleRate) {
            releaseLocked()
            open(sampleRate)
        }
        queue.offer(pcm)
        route
    }

    /** Stops at once and drops whatever is queued. */
    fun stop() = synchronized(lock) { releaseLocked() }

    private fun open(sampleRate: Int) {
        val speaker = findSpeaker()
        val alarm = useAlarmRoute || speaker == null
        val attributes = AudioAttributes.Builder()
            .setUsage(if (alarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val format = AudioFormat.Builder()
            .setSampleRate(sampleRate)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .build()
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val t = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(format)
            .setBufferSizeInBytes(maxOf(minBuffer, sampleRate)) // about half a second
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        route = when {
            alarm -> "alarm"
            speaker != null && t.setPreferredDevice(speaker) -> "speaker"
            else -> "default"
        }
        if (route != "alarm") {
            t.addOnRoutingChangedListener(
                AudioRouting.OnRoutingChangedListener { router ->
                    val device = router.routedDevice
                    if (device != null && device.type != AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
                        useAlarmRoute = true
                    }
                },
                null,
            )
        }
        t.play()
        track = t
        rate = sampleRate
        val q = LinkedBlockingQueue<ByteArray>()
        queue = q
        writer = Thread({
            try {
                while (!Thread.currentThread().isInterrupted) {
                    val chunk = q.take()
                    t.write(chunk, 0, chunk.size)
                }
            } catch (e: InterruptedException) {
                // Stopped.
            } catch (e: IllegalStateException) {
                // The track was released while writing.
            }
        }, "room-speaker").also { it.start() }
    }

    private fun releaseLocked() {
        writer?.interrupt()
        writer = null
        queue.clear()
        track?.let {
            try {
                it.pause()
                it.flush()
                it.stop()
            } catch (e: IllegalStateException) {
                // Already stopped.
            }
            it.release()
        }
        track = null
        rate = 0
    }

    private fun findSpeaker(): AudioDeviceInfo? {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
    }
}

package com.scoai.voice.openai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var roomSpeaker: RoomSpeaker? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val speaker = RoomSpeaker(applicationContext)
        roomSpeaker = speaker
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scoai.voice/room_speaker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val pcm = call.argument<ByteArray>("pcm")
                        val rate = call.argument<Int>("rate") ?: 24000
                        if (pcm == null) {
                            result.error("bad_args", "pcm is missing", null)
                        } else {
                            result.success(speaker.play(pcm, rate))
                        }
                    }
                    "stop" -> {
                        speaker.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        roomSpeaker?.stop()
        super.onDestroy()
    }
}

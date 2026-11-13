import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../live/audio_ports.dart';
import '../openai/realtime_translate.dart' show pcmSampleRate;

/// Microphone via the `record` plugin: 24 kHz 16-bit mono PCM, with the
/// platform echo canceller so read-aloud is not re-translated.
class RecordMic implements MicSource {
  AudioRecorder? _rec;

  @override
  Future<bool> ensurePermission() => (_rec ??= AudioRecorder()).hasPermission();

  @override
  Future<Stream<Uint8List>> start({bool nearField = false}) async {
    final rec = _rec ??= AudioRecorder();
    return rec.startStream(RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: pcmSampleRate,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      autoGain: true,
      // The meeting is the room, not the user's headset microphone.
      device: await _builtInMic(rec),
      androidConfig: const AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceCommunication,
      ),
    ));
  }

  Future<InputDevice?> _builtInMic(AudioRecorder rec) async {
    try {
      final devices = await rec.listInputDevices();
      for (final d in devices) {
        if (d.type == InputDeviceType.builtIn) return d;
      }
    } on Object {
      // Fall back to Android's choice.
    }
    return null;
  }

  @override
  Future<void> stop() async {
    final rec = _rec;
    if (rec == null) return;
    if (await rec.isRecording() || await rec.isPaused()) await rec.stop();
  }
}

/// Streams PCM to the speaker with `flutter_pcm_sound`.
class PcmSpeaker implements PcmSink {
  int? _rate;

  @override
  Future<void> play(Uint8List pcm, int sampleRate) async {
    if (_rate != sampleRate) {
      if (_rate != null) await FlutterPcmSound.release();
      await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
      await FlutterPcmSound.setFeedThreshold(sampleRate ~/ 10);
      _rate = sampleRate;
    }
    final copy = Uint8List.fromList(pcm);
    await FlutterPcmSound.feed(PcmArrayInt16(bytes: copy.buffer.asByteData()));
  }

  @override
  Future<void> stop() async {
    if (_rate == null) return;
    _rate = null;
    await FlutterPcmSound.release();
  }
}

class WakelockAwake implements ScreenAwake {
  const WakelockAwake();
  @override
  Future<void> set(bool on) => on ? WakelockPlus.enable() : WakelockPlus.disable();
}

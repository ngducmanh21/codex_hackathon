import 'dart:typed_data';

/// Microphone producing 24 kHz 16-bit mono PCM.
abstract class MicSource {
  /// Asks for the microphone permission if needed.
  Future<bool> ensurePermission();

  Future<Stream<Uint8List>> start({bool nearField = false});

  Future<void> stop();
}

/// Plays 16-bit mono PCM as it arrives.
abstract class PcmSink {
  Future<void> play(Uint8List pcm, int sampleRate);

  /// Stops and drops whatever is queued.
  Future<void> stop();
}

/// Keeps the screen on while recording.
abstract class ScreenAwake {
  Future<void> set(bool on);
}

class NoScreenAwake implements ScreenAwake {
  const NoScreenAwake();
  @override
  Future<void> set(bool on) async {}
}

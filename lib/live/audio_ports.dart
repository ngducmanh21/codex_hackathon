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

/// Keeps the recording alive while the screen is off or the user is in
/// another app, and shows what is being recorded.
///
/// On Android this is a foreground service of type "microphone": without
/// one the system stops the microphone as soon as the app leaves the
/// foreground.
abstract class BackgroundRecording {
  Future<void> start({required String title, required String text});

  /// Refreshes the notification's running time.
  Future<void> update({required String title, required String text});

  Future<void> stop();
}

/// For tests and hosts without a service.
class NoBackgroundRecording implements BackgroundRecording {
  const NoBackgroundRecording();
  @override
  Future<void> start({required String title, required String text}) async {}
  @override
  Future<void> update({required String title, required String text}) async {}
  @override
  Future<void> stop() async {}
}

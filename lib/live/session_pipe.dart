import 'dart:async';
import 'dart:typed_data';

import '../openai/realtime_translate.dart';

typedef SessionOpener = Future<TranslateSession> Function(TranslateConfig config);

/// Routes microphone audio to the current translation session.
///
/// While no session is attached (connecting, reconnecting, rolling over to
/// a new session) audio is buffered up to [maxBuffer] and sent as soon as
/// the next session attaches; anything beyond is dropped and reported via
/// [droppedAudio].
class SessionPipe {
  SessionPipe({
    required this.opener,
    required this.onEvent,
    this.maxBuffer = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final SessionOpener opener;
  final void Function(TranslateEvent event, TranslateSession from) onEvent;
  final Duration maxBuffer;
  final DateTime Function() _now;

  TranslateSession? _active;
  final _buffer = BytesBuilder(copy: false);
  final _lastText = Expando<DateTime>();
  final _subs = <TranslateSession, StreamSubscription<TranslateEvent>>{};

  /// Audio was lost because the buffer overflowed while disconnected.
  bool droppedAudio = false;

  /// Set before a [SessionEnded] is forwarded: whether the session that
  /// ended was the one receiving audio (as opposed to one being drained).
  bool lastEndedWasActive = false;

  TranslateSession? get active => _active;

  int get _maxBufferBytes => maxBuffer.inMilliseconds * pcmSampleRate * 2 ~/ 1000;

  /// Bytes of audio waiting for a session.
  int get bufferedBytes => _buffer.length;

  /// Opens a session and makes it the one receiving audio.
  Future<TranslateSession> attach(TranslateConfig config) async {
    final s = await opener(config);
    if (_disposed) {
      // The screen closed while connecting: do not leave a session open.
      await s.close(timeout: const Duration(seconds: 1));
      throw StateError('pipe disposed');
    }
    _lastText[s] = _now();
    _subs[s] = s.events.listen((e) {
      if (e is SourceDelta || e is TranslationDelta) _lastText[s] = _now();
      if (e is SessionEnded) {
        _subs.remove(s);
        lastEndedWasActive = identical(_active, s);
        if (lastEndedWasActive) _active = null;
      }
      onEvent(e, s);
    });
    _active = s;
    if (_buffer.length > 0) s.append(_buffer.takeBytes());
    return s;
  }

  /// Stops sending audio to the current session (new audio is buffered)
  /// and returns it, so the caller can drain it.
  TranslateSession? detach() {
    final s = _active;
    _active = null;
    return s;
  }

  void push(Uint8List pcm) {
    final s = _active;
    if (s != null && s.isOpen) {
      s.append(pcm);
      return;
    }
    if (_buffer.length + pcm.length > _maxBufferBytes) {
      droppedAudio = true;
      return;
    }
    _buffer.add(pcm);
  }

  void clearBuffer() => _buffer.clear();

  /// Lets [s] finish what it heard: keeps feeding real-time silence until
  /// no text arrived for [quiet] (after at least [minWait]) or [maxWait]
  /// passes, then closes it.
  Future<void> drain(
    TranslateSession s, {
    Duration minWait = const Duration(milliseconds: 800),
    Duration quiet = const Duration(milliseconds: 1500),
    Duration maxWait = const Duration(seconds: 6),
    Duration tick = const Duration(milliseconds: 200),
  }) async {
    final start = _now();
    while (s.isOpen) {
      final now = _now();
      final waited = now.difference(start);
      if (waited >= maxWait) break;
      final last = _lastText[s] ?? start;
      final since = now.difference(last.isAfter(start) ? last : start);
      if (waited >= minWait && since >= quiet) break;
      s.appendSilence(tick);
      await Future<void>.delayed(tick);
    }
    await s.close();
  }

  bool _disposed = false;

  Future<void> dispose() async {
    _disposed = true;
    final s = _active;
    _active = null;
    if (s != null) await s.close(timeout: const Duration(seconds: 1));
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
    _buffer.clear();
  }
}

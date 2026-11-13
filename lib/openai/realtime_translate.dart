import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/lang.dart';
import 'openai_error.dart';

/// Client for OpenAI's live speech translation sessions
/// (`gpt-realtime-translate` over WebSocket).
///
/// Wire format, per OpenAI's realtime translation reference (checked
/// 2026-11-13):
/// - connect to `wss://api.openai.com/v1/realtime/translations?model=…`;
/// - send `session.update` with `audio.output.language`;
/// - stream `session.input_audio_buffer.append` with base64 24 kHz PCM16
///   mono in 200 ms chunks, silence included, for as long as the session
///   is open;
/// - receive `session.input_transcript.delta` (what was said),
///   `session.output_transcript.delta` (translation text) and
///   `session.output_audio.delta` (translated speech). There are no
///   per-sentence "done" events: callers split sentences themselves.
/// - end with `session.close` and wait for `session.closed`.

const translateModel = 'gpt-realtime-translate';

/// Transcription model for the source captions inside a translation
/// session, as in OpenAI's own example.
const sourceTranscriptionModel = 'gpt-realtime-whisper';

const pcmSampleRate = 24000;

/// 200 ms of 16-bit mono audio at 24 kHz.
const chunkBytes = pcmSampleRate * 2 ~/ 5;

enum NoiseReduction { nearField, farField }

class TranslateConfig {
  const TranslateConfig({
    required this.target,
    this.noise = NoiseReduction.farField,
    this.model = translateModel,
    this.transcriptionModel = sourceTranscriptionModel,
  });

  final Lang target;
  final NoiseReduction noise;
  final String model;
  final String transcriptionModel;

  Map<String, Object?> sessionUpdate() => {
        'type': 'session.update',
        'session': {
          'audio': {
            'input': {
              'transcription': {'model': transcriptionModel},
              'noise_reduction': {
                'type': noise == NoiseReduction.nearField ? 'near_field' : 'far_field',
              },
            },
            'output': {'language': target.code},
          },
        },
      };
}

sealed class TranslateEvent {
  const TranslateEvent();
}

class SessionReady extends TranslateEvent {
  const SessionReady(this.sessionId, this.expiresAt);
  final String? sessionId;
  final DateTime? expiresAt;
}

/// Text of what was said, appended as it is recognised.
class SourceDelta extends TranslateEvent {
  const SourceDelta(this.text, this.elapsedMs);
  final String text;
  final int? elapsedMs;
}

/// Translation text, appended as it is produced.
class TranslationDelta extends TranslateEvent {
  const TranslationDelta(this.text, this.elapsedMs);
  final String text;
  final int? elapsedMs;
}

/// Translated speech: 16-bit little-endian PCM.
class AudioDelta extends TranslateEvent {
  const AudioDelta(this.pcm, this.sampleRate);
  final Uint8List pcm;
  final int sampleRate;
}

/// An `error` event. OpenAI says these are mostly recoverable and the
/// session stays open.
class SessionWarning extends TranslateEvent {
  const SessionWarning(this.code, this.message);
  final String? code;
  final String message;
}

/// The session ended. [error] is null after a normal `session.close`.
class SessionEnded extends TranslateEvent {
  const SessionEnded({this.error});
  final Object? error;
}

/// A text WebSocket. Abstract so tests can drive the protocol with a fake.
abstract class WsLink {
  Stream<String> get messages;
  void send(String text);
  Future<void> close();
}

typedef WsConnector = Future<WsLink> Function(Uri url, Map<String, String> headers);

Future<WsLink> ioWsConnector(Uri url, Map<String, String> headers) async {
  try {
    final ws = await WebSocket.connect(url.toString(), headers: headers)
        .timeout(const Duration(seconds: 15));
    ws.pingInterval = const Duration(seconds: 20);
    return _IoWsLink(ws);
  } on WebSocketException catch (e) {
    // The upgrade failed: usually a bad key (401) or no access to the model.
    throw OpenAiException('Không mở được phiên dịch: ${e.message}', code: 'ws_upgrade');
  } on TimeoutException {
    throw const OpenAiException('Không kết nối được tới OpenAI (hết thời gian chờ).');
  } on SocketException catch (e) {
    throw OpenAiException('Không có mạng: ${e.message}');
  }
}

class _IoWsLink implements WsLink {
  _IoWsLink(this._ws);
  final WebSocket _ws;

  @override
  Stream<String> get messages => _ws.where((m) => m is String).cast<String>();

  @override
  void send(String text) => _ws.add(text);

  @override
  Future<void> close() => _ws.close();
}

/// One open translation session.
class TranslateSession {
  TranslateSession._(this._link, this.config) {
    _sub = _link.messages.listen(
      _onMessage,
      onError: (Object e) => _end(e),
      onDone: () => _end(_closing ? null : const OpenAiException('Phiên dịch bị ngắt.')),
    );
  }

  final WsLink _link;
  final TranslateConfig config;
  late final StreamSubscription<String> _sub;
  final _events = StreamController<TranslateEvent>.broadcast();
  final _pending = BytesBuilder(copy: false);
  final _closed = Completer<void>();
  bool _closing = false;
  int _bytesSent = 0;

  /// Opens a session and sends its configuration.
  static Future<TranslateSession> open({
    required String apiKey,
    required TranslateConfig config,
    WsConnector connector = ioWsConnector,
    Uri? baseUrl,
  }) async {
    final url = (baseUrl ?? Uri.parse('wss://api.openai.com/v1/realtime/translations'))
        .replace(queryParameters: {'model': config.model});
    final link = await connector(url, {'Authorization': 'Bearer $apiKey'});
    final session = TranslateSession._(link, config);
    link.send(jsonEncode(config.sessionUpdate()));
    return session;
  }

  Stream<TranslateEvent> get events => _events.stream;

  bool get isOpen => !_closed.isCompleted;

  /// Audio sent so far; this is what OpenAI bills.
  Duration get audioSent =>
      Duration(microseconds: _bytesSent * 1000000 ~/ (pcmSampleRate * 2));

  /// Queues 16-bit PCM and sends it in 200 ms chunks.
  void append(Uint8List pcm) {
    if (_closing || !isOpen) return;
    _pending.add(pcm);
    if (_pending.length < chunkBytes) return;
    final all = _pending.takeBytes();
    var offset = 0;
    while (all.length - offset >= chunkBytes) {
      _sendChunk(Uint8List.sublistView(all, offset, offset + chunkBytes));
      offset += chunkBytes;
    }
    if (offset < all.length) _pending.add(Uint8List.sublistView(all, offset));
  }

  /// Sends [duration] of silence, so the model finishes the last sentence.
  void appendSilence(Duration duration) {
    final bytes = (duration.inMicroseconds * pcmSampleRate * 2 ~/ 1000000) & ~1;
    append(Uint8List(bytes));
  }

  void _sendChunk(Uint8List chunk) {
    _link.send(jsonEncode({
      'type': 'session.input_audio_buffer.append',
      'audio': base64Encode(chunk),
    }));
    _bytesSent += chunk.length;
  }

  /// Changes "Dịch sang" on the open session.
  void updateTarget(Lang target) {
    if (_closing || !isOpen) return;
    _link.send(jsonEncode({
      'type': 'session.update',
      'session': {
        'audio': {
          'output': {'language': target.code},
        },
      },
    }));
  }

  /// Ends the session: sends any partial chunk, then `session.close`, and
  /// waits for `session.closed` (or [timeout]).
  Future<void> close({Duration timeout = const Duration(seconds: 3)}) async {
    if (!isOpen) return;
    if (!_closing) {
      if (_pending.length > 0) _sendChunk(_pending.takeBytes());
      _closing = true;
      try {
        _link.send(jsonEncode({'type': 'session.close'}));
      } on Object {
        // The socket may already be gone.
      }
    }
    try {
      await _closed.future.timeout(timeout);
    } on TimeoutException {
      _end(null);
    }
  }

  void _onMessage(String raw) {
    final Map<String, Object?> e;
    try {
      e = (jsonDecode(raw) as Map).cast<String, Object?>();
    } on Object {
      return;
    }
    switch (e['type']) {
      case 'session.created':
      case 'session.updated':
        final s = (e['session'] as Map?)?.cast<String, Object?>();
        final exp = (s?['expires_at'] as num?)?.toInt();
        _emit(SessionReady(
          s?['id'] as String?,
          exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
        ));
      case 'session.input_transcript.delta':
        final d = e['delta'] as String? ?? '';
        if (d.isNotEmpty) _emit(SourceDelta(d, (e['elapsed_ms'] as num?)?.toInt()));
      case 'session.output_transcript.delta':
        final d = e['delta'] as String? ?? '';
        if (d.isNotEmpty) _emit(TranslationDelta(d, (e['elapsed_ms'] as num?)?.toInt()));
      case 'session.output_audio.delta':
        final d = e['delta'] as String?;
        if (d == null || d.isEmpty) return;
        _emit(AudioDelta(
          base64Decode(d),
          (e['sample_rate'] as num?)?.toInt() ?? pcmSampleRate,
        ));
      case 'error':
        final err = (e['error'] as Map?)?.cast<String, Object?>() ?? const {};
        _emit(SessionWarning(
          err['code'] as String?,
          err['message'] as String? ?? 'Lỗi không rõ từ phiên dịch.',
        ));
      case 'session.closed':
        _end(null);
    }
  }

  void _emit(TranslateEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _end(Object? error) {
    if (_closed.isCompleted) return;
    _closed.complete();
    _emit(SessionEnded(error: error));
    _events.close();
    _sub.cancel();
    _link.close();
  }
}

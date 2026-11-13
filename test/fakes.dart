import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:scoai_voice_openai/live/audio_ports.dart';
import 'package:scoai_voice_openai/openai/realtime_translate.dart';

/// A scripted translation server on the other side of a [WsLink].
class FakeWs implements WsLink {
  FakeWs(this.url, this.headers, {this.ackClose = true});

  final Uri url;
  final Map<String, String> headers;

  /// Answer `session.close` with `session.closed`.
  bool ackClose;

  final sent = <Map<String, Object?>>[];
  final _in = StreamController<String>();
  bool closedByClient = false;

  @override
  Stream<String> get messages => _in.stream;

  @override
  void send(String text) {
    final e = (jsonDecode(text) as Map).cast<String, Object?>();
    sent.add(e);
    if (e['type'] == 'session.close' && ackClose) {
      scheduleMicrotask(() => server({'type': 'session.closed'}));
    }
  }

  @override
  Future<void> close() async {
    closedByClient = true;
    if (!_in.isClosed) await _in.close();
  }

  void server(Map<String, Object?> event) {
    if (!_in.isClosed) _in.add(jsonEncode(event));
  }

  void source(String delta, [int? ms]) =>
      server({'type': 'session.input_transcript.delta', 'delta': delta, 'elapsed_ms': ms});

  void translation(String delta, [int? ms]) =>
      server({'type': 'session.output_transcript.delta', 'delta': delta, 'elapsed_ms': ms});

  void audio(List<int> pcm) => server({
        'type': 'session.output_audio.delta',
        'delta': base64Encode(pcm),
        'sample_rate': 24000,
        'channels': 1,
        'format': 'pcm16',
      });

  /// The connection drops without a `session.closed`.
  Future<void> drop() async {
    if (!_in.isClosed) await _in.close();
  }

  List<Map<String, Object?>> ofType(String type) => [for (final e in sent) if (e['type'] == type) e];

  /// Total audio bytes received in append events.
  int get audioBytes =>
      ofType('session.input_audio_buffer.append').fold(0, (n, e) => n + base64Decode(e['audio'] as String).length);
}

/// Opens [TranslateSession]s against [FakeWs] servers and keeps them.
class FakeTranslateBackend {
  final servers = <FakeWs>[];
  final configs = <TranslateConfig>[];
  int failNext = 0;

  Future<TranslateSession> open(TranslateConfig config) {
    configs.add(config);
    return TranslateSession.open(
      apiKey: 'sk-test-0000',
      config: config,
      connector: (url, headers) async {
        if (failNext > 0) {
          failNext--;
          throw StateError('connect failed');
        }
        final ws = FakeWs(url, headers);
        servers.add(ws);
        return ws;
      },
    );
  }

  FakeWs get last => servers.last;
}

class FakeMic implements MicSource {
  bool permission = true;
  StreamController<Uint8List>? _c;
  int starts = 0;
  int stops = 0;

  bool get running => _c != null;

  @override
  Future<bool> ensurePermission() async => permission;

  @override
  Future<Stream<Uint8List>> start({bool nearField = false}) async {
    starts++;
    _c = StreamController<Uint8List>();
    return _c!.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    final c = _c;
    _c = null;
    // Closing a stream whose listener already cancelled may never complete.
    unawaited(c?.close());
  }

  /// Pushes [ms] of audio (non-zero bytes so it differs from silence).
  void speak(int ms) {
    final bytes = Uint8List(ms * 48)..fillRange(0, ms * 48, 7);
    _c?.add(bytes);
  }
}

class FakeSpeaker implements PcmSink {
  final played = <Uint8List>[];
  int stops = 0;

  @override
  Future<void> play(Uint8List pcm, int sampleRate) async => played.add(pcm);

  @override
  Future<void> stop() async => stops++;
}

/// Lets queued microtasks and short timers run.
Future<void> settleAsync([int ms = 20]) => Future<void>.delayed(Duration(milliseconds: ms));

/// Waits until [condition] holds, failing after [timeout].
Future<void> waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

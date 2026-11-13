import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/openai/openai_error.dart';
import 'package:scoai_voice_openai/openai/realtime_translate.dart';

import '../fakes.dart';

void main() {
  late FakeWs ws;

  Future<TranslateSession> open({Lang target = Lang.vi, bool ackClose = true}) => TranslateSession.open(
        apiKey: 'sk-secret-1234',
        config: TranslateConfig(target: target),
        connector: (url, headers) async => ws = FakeWs(url, headers, ackClose: ackClose),
      );

  test('connects with the model in the URL and the key only in the header', () async {
    final s = await open(target: Lang.zh);
    expect(ws.url.toString(), 'wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate');
    expect(ws.headers['Authorization'], 'Bearer sk-secret-1234');
    final update = ws.sent.single;
    expect(update['type'], 'session.update');
    expect(update, {
      'type': 'session.update',
      'session': {
        'audio': {
          'input': {
            'transcription': {'model': 'gpt-realtime-whisper'},
            'noise_reduction': {'type': 'far_field'},
          },
          'output': {'language': 'zh'},
        },
      },
    });
    await s.close();
  });

  test('sends audio in 200 ms base64 chunks and keeps the remainder', () async {
    final s = await open();
    final pcm = Uint8List.fromList(List.generate(chunkBytes * 2 + 100, (i) => i % 251));
    s.append(Uint8List.sublistView(pcm, 0, 5000));
    expect(ws.ofType('session.input_audio_buffer.append'), isEmpty);
    s.append(Uint8List.sublistView(pcm, 5000));
    final chunks = ws.ofType('session.input_audio_buffer.append');
    expect(chunks, hasLength(2));
    final decoded = [for (final c in chunks) ...base64Decode(c['audio'] as String)];
    expect(decoded, pcm.sublist(0, chunkBytes * 2));
    expect(s.audioSent, const Duration(milliseconds: 400));

    await s.close();
    // The 100-byte tail goes out before session.close.
    final types = ws.sent.map((e) => e['type']).toList();
    expect(types.sublist(types.length - 2), ['session.input_audio_buffer.append', 'session.close']);
    expect(ws.audioBytes, pcm.length);
    expect(s.isOpen, isFalse);
  });

  test('maps server events to typed events', () async {
    final s = await open();
    final events = <TranslateEvent>[];
    s.events.listen(events.add);
    ws.server({
      'type': 'session.created',
      'session': {'id': 'sess_1', 'expires_at': 1800000000},
    });
    ws.source('如果订单', 1200);
    ws.translation('Nếu đơn', 1400);
    ws.audio([1, 2, 3, 4]);
    ws.server({
      'type': 'error',
      'error': {'type': 'invalid_request_error', 'code': 'invalid_event', 'message': 'bad'},
    });
    ws.server({'type': 'something.new'});
    await settleAsync();

    expect(events[0], isA<SessionReady>().having((e) => e.sessionId, 'id', 'sess_1'));
    expect((events[0] as SessionReady).expiresAt, DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000));
    expect(events[1], isA<SourceDelta>().having((e) => e.text, 'text', '如果订单').having((e) => e.elapsedMs, 'ms', 1200));
    expect(events[2], isA<TranslationDelta>().having((e) => e.text, 'text', 'Nếu đơn'));
    expect(events[3], isA<AudioDelta>().having((e) => e.pcm, 'pcm', [1, 2, 3, 4]).having((e) => e.sampleRate, 'rate', 24000));
    expect(events[4], isA<SessionWarning>().having((e) => e.code, 'code', 'invalid_event'));
    expect(events, hasLength(5), reason: 'unknown events are ignored');
    // An error event does not end the session.
    expect(s.isOpen, isTrue);
    await s.close();
    await settleAsync();
    expect(events.last, isA<SessionEnded>().having((e) => e.error, 'error', isNull));
  });

  test('a dropped connection ends the session with an error', () async {
    final s = await open();
    final ended = s.events.firstWhere((e) => e is SessionEnded);
    await ws.drop();
    final e = await ended as SessionEnded;
    expect(e.error, isA<OpenAiException>());
    expect(s.isOpen, isFalse);
    // Appending after the end is a no-op, not a crash.
    s.append(Uint8List(chunkBytes));
  });

  test('close gives up when the server never confirms', () async {
    final s = await open(ackClose: false);
    await s.close(timeout: const Duration(milliseconds: 50));
    expect(s.isOpen, isFalse);
    expect(ws.closedByClient, isTrue);
  });

  test('updateTarget changes only the output language', () async {
    final s = await open();
    s.updateTarget(Lang.en);
    expect(ws.sent.last, {
      'type': 'session.update',
      'session': {
        'audio': {
          'output': {'language': 'en'},
        },
      },
    });
    await s.close();
  });

  test('appendSilence sends zeros of the right length', () async {
    final s = await open();
    s.appendSilence(const Duration(milliseconds: 400));
    final chunks = ws.ofType('session.input_audio_buffer.append');
    expect(chunks, hasLength(2));
    expect(base64Decode(chunks.first['audio'] as String).every((b) => b == 0), isTrue);
    await s.close();
  });

  test('connector failure surfaces and leaks no key', () async {
    Object? error;
    try {
      await TranslateSession.open(
        apiKey: 'sk-secret-1234',
        config: const TranslateConfig(target: Lang.vi),
        connector: (url, headers) async => throw const OpenAiException('Không mở được phiên dịch: 401'),
      );
    } on Object catch (e) {
      error = e;
    }
    expect(error, isA<OpenAiException>());
    expect(error.toString(), isNot(contains('sk-secret')));
  });
}

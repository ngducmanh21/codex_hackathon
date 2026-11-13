import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/domain/records.dart';
import 'package:scoai_voice_openai/openai/openai_error.dart';
import 'package:scoai_voice_openai/openai/transcribe_client.dart';

void main() {
  test('uploads the file as multipart with model, language and a context prompt', () async {
    late String body;
    late http.BaseRequest seen;
    final client = TranscribeClient(
      key: () async => 'sk-up',
      httpClient: MockClient((req) async {
        seen = req;
        body = latin1.decode(req.bodyBytes);
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'text': 'Hello there. 你好。',
            'languages': [
              {'code': 'en'},
              {'code': 'zh'},
            ],
            'usage': {'type': 'duration', 'seconds': 12.5},
          })),
          200,
        );
      }),
    );
    final r = await client.transcribe(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'call.m4a',
      language: Lang.en,
      context: const MeetingContext(topic: 'Supplier call', terms: [Term('MOQ', 'số lượng tối thiểu')]),
    );
    expect(seen.url.path, '/v1/audio/transcriptions');
    expect(seen.headers['Authorization'], 'Bearer sk-up');
    expect(seen.headers['content-type'], startsWith('multipart/form-data'));
    expect(body, contains('name="model"\r\n\r\ngpt-transcribe'));
    expect(body, contains('name="language"\r\n\r\nen'));
    expect(body, contains('name="prompt"\r\n\r\nSupplier call. MOQ'));
    expect(body, contains('filename="call.m4a"'));
    expect(r.text, 'Hello there. 你好。');
    expect(r.languages, [Lang.en, Lang.zh]);
    expect(r.seconds, 12.5);
  });

  test('auto-detect sends no language and no empty prompt', () async {
    late String body;
    final client = TranscribeClient(
      key: () async => 'sk-up',
      httpClient: MockClient((req) async {
        body = latin1.decode(req.bodyBytes);
        return http.Response.bytes(utf8.encode('{"text":"Xin chào"}'), 200);
      }),
    );
    await client.transcribe(bytes: Uint8List(4), fileName: 'a.wav');
    expect(body, isNot(contains('name="language"')));
    expect(body, isNot(contains('name="prompt"')));
  });

  test('files over 25 MB are refused before any upload', () async {
    var calls = 0;
    final client = TranscribeClient(
      key: () async => 'sk-up',
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.transcribe(bytes: Uint8List(maxUploadBytes + 1), fileName: 'big.wav'),
      throwsA(isA<OpenAiException>().having((e) => e.code, 'code', 'file_too_large')),
    );
    expect(calls, 0);
  });

  test('server errors carry the status and message', () async {
    final client = TranscribeClient(
      key: () async => 'sk-up',
      httpClient: MockClient((_) async => http.Response('{"error":{"message":"Rate limit reached","code":"rate_limit_exceeded"}}', 429)),
    );
    await expectLater(
      client.transcribe(bytes: Uint8List(4), fileName: 'a.wav'),
      throwsA(isA<OpenAiException>().having((e) => e.isRateLimit, 'rate limit', isTrue)),
    );
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/domain/records.dart';
import 'package:scoai_voice_openai/openai/openai_error.dart';
import 'package:scoai_voice_openai/openai/responses_client.dart';
import 'package:scoai_voice_openai/openai/text_ai.dart';
import 'package:scoai_voice_openai/storage/key_store.dart';

/// A Responses API body whose message carries [text], after a reasoning
/// item (the text is not guaranteed to be at output[0]).
String responseBody(String text, {int input = 120, int output = 30, String model = 'gpt-6-luna-2026-10-01'}) => jsonEncode({
      'id': 'resp_1',
      'object': 'response',
      'model': model,
      'output': [
        {'type': 'reasoning', 'id': 'rs_1', 'summary': []},
        {
          'type': 'message',
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': text, 'annotations': []},
          ],
        },
      ],
      'usage': {'input_tokens': input, 'output_tokens': output, 'total_tokens': input + output},
    });

void main() {
  group('ResponsesClient', () {
    test('sends a strict JSON-schema request without storing it', () async {
      late http.Request seen;
      final client = ResponsesClient(
        key: () async => 'sk-abc',
        httpClient: MockClient((req) async {
          seen = req;
          return http.Response.bytes(utf8.encode(responseBody('{"ok":true}')), 200);
        }),
      );
      final r = await client.create(
        model: 'gpt-6-luna',
        instructions: 'Do it',
        input: 'hello',
        schema: const {'type': 'object'},
        schemaName: 'thing',
      );
      expect(seen.url.toString(), 'https://api.openai.com/v1/responses');
      expect(seen.headers['Authorization'], 'Bearer sk-abc');
      final body = jsonDecode(seen.body) as Map;
      expect(body['model'], 'gpt-6-luna');
      expect(body['instructions'], 'Do it');
      expect(body['input'], 'hello');
      expect(body['store'], false);
      expect(body['reasoning'], {'effort': 'none'});
      expect(body['text'], {
        'format': {'type': 'json_schema', 'name': 'thing', 'schema': {'type': 'object'}, 'strict': true},
      });
      expect(r.text, '{"ok":true}');
      expect(r.inputTokens, 120);
      expect(r.outputTokens, 30);
    });

    test('HTTP errors become OpenAiException without the key', () async {
      final client = ResponsesClient(
        key: () async => 'sk-very-secret',
        httpClient: MockClient((_) async => http.Response(
              '{"error":{"message":"Incorrect API key provided","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}',
              401,
            )),
      );
      final err = await client
          .create(model: 'm', instructions: 'i', input: 'x')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(err, isA<OpenAiException>());
      final e = err! as OpenAiException;
      expect(e.status, 401);
      expect(e.isAuth, isTrue);
      expect(e.message, 'Incorrect API key provided');
      expect(e.toString(), isNot(contains('sk-very-secret')));
      expect(e.userMessage, contains('Khoá OpenAI không hợp lệ'));
    });

    test('a refusal or empty output is an error, not empty text', () {
      final refusal = jsonEncode({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'refusal', 'refusal': 'I cannot help with that.'},
            ],
          },
        ],
      });
      expect(() => parseResponse(refusal), throwsA(isA<OpenAiException>().having((e) => e.code, 'code', 'refusal')));
      expect(() => parseResponse('{"output":[]}'), throwsA(isA<OpenAiException>()));
    });

    test('no saved key fails before any request', () async {
      var calls = 0;
      final client = ResponsesClient(
        key: keyProviderFor(MemoryKeyStore()),
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(client.create(model: 'm', instructions: 'i', input: 'x'), throwsA(isA<MissingKeyException>()));
      expect(calls, 0);
    });
  });

  group('TextAi', () {
    late List<Map<String, Object?>> requests;
    late List<String> replies;
    final usage = <(String, int, int)>[];

    TextAi ai() => TextAi(
          ResponsesClient(
            key: () async => 'sk-x',
            httpClient: MockClient((req) async {
              requests.add((jsonDecode(req.body) as Map).cast<String, Object?>());
              return http.Response.bytes(utf8.encode(responseBody(replies.removeAt(0))), 200);
            }),
          ),
          onUsage: (m, i, o) => usage.add((m, i, o)),
        );

    setUp(() {
      requests = [];
      replies = [];
      usage.clear();
    });

    test('translate puts the glossary in the instructions and batches long lists', () async {
      final sentences = List.generate(45, (i) => '句子$i。');
      replies
        ..add(jsonEncode({'translations': List.generate(40, (i) => 'Câu $i.')}))
        ..add(jsonEncode({'translations': List.generate(5, (i) => 'Câu ${40 + i}.')}));
      const ctx = MeetingContext(topic: 'Linh kiện', terms: [Term('贴片', 'dán SMT')]);
      final out = await ai().translate(sentences, to: Lang.vi, context: ctx);

      expect(out, hasLength(45));
      expect(out.last, 'Câu 44.');
      expect(requests, hasLength(2));
      final instr = requests.first['instructions'] as String;
      expect(instr, contains('Vietnamese'));
      expect(instr, contains('贴片 => dán SMT'));
      expect(instr, contains('Topic: Linh kiện'));
      expect(jsonDecode(requests.first['input'] as String), {'segments': sentences.sublist(0, 40)});
      expect(requests.first['model'], fastTextModel);
      expect(usage, hasLength(2));
      expect(usage.first.$1, 'gpt-6-luna-2026-10-01');
    });

    test('translate rejects a reply with the wrong number of lines', () async {
      replies.add(jsonEncode({'translations': ['một']}));
      await expectLater(
        ai().translate(['a.', 'b.'], to: Lang.vi),
        throwsA(isA<OpenAiException>().having((e) => e.code, 'code', 'bad_shape')),
      );
    });

    final meeting = LibraryItem(
      id: 'm1',
      kind: ItemKind.meeting,
      title: 'Họp',
      createdAt: DateTime(2026, 11, 12),
      duration: const Duration(minutes: 42),
      targetLang: Lang.vi,
      sentences: const [
        Sentence(at: Duration(minutes: 12, seconds: 21), source: '单价两块三五。', translation: 'Đơn giá 2,35.', lang: Lang.zh),
        Sentence(at: Duration(minutes: 13), source: 'Đồng ý.', translation: '', lang: Lang.vi),
      ],
    );

    test('summarize uses the analysis model and parses the structured summary', () async {
      replies.add(jsonEncode({
        'overview': 'Hai bên chốt giá.',
        'decisions': ['Đơn giá 2,35 USD'],
        'actions': [
          {'task': 'Gửi BOM', 'owner': 'Bên mình', 'due': 'thứ Sáu'},
        ],
        'open_questions': <String>[],
      }));
      final s = await ai().summarize(meeting, readingLang: Lang.vi);
      expect(s.overview, 'Hai bên chốt giá.');
      expect(s.actions.single.owner, 'Bên mình');
      expect(requests.single['model'], qualityTextModel);
      expect(requests.single['input'], contains('[12:21] 单价两块三五。 || Đơn giá 2,35.'));
      expect(requests.single['input'], contains('[13:00] Đồng ý.\n'));
    });

    test('ask returns the answer with its transcript references', () async {
      replies.add(jsonEncode({'answer': '2,35 USD/chiếc.', 'refs': ['12:21']}));
      final qa = await ai().ask(meeting, 'Giá cuối là bao nhiêu?');
      expect(qa.question, 'Giá cuối là bao nhiêu?');
      expect(qa.answer, '2,35 USD/chiếc.');
      expect(qa.refs, ['12:21']);
      expect(requests.single['input'], endsWith('QUESTION:\nGiá cuối là bao nhiêu?'));
    });

    test('uploads are labelled by line number, the user\'s replies as Me', () {
      final upload = meeting.copyWith().toJson()..['kind'] = 'upload';
      final text = transcriptForPrompt(LibraryItem.fromJson(upload));
      expect(text, contains('[#1] 单价两块三五。'));
      final replied = meeting.copyWith(sentences: const [
        Sentence(at: Duration.zero, source: 'Xin chào', translation: '你好', lang: Lang.vi, speaker: 0),
      ]);
      expect(transcriptForPrompt(replied), contains('[00:00] Me: Xin chào || 你好'));
    });
  });
}

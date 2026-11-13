import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/live/meeting_controller.dart';
import 'package:scoai_voice_openai/openai/responses_client.dart';
import 'package:scoai_voice_openai/openai/text_ai.dart';
import 'package:scoai_voice_openai/storage/library_store.dart';

import '../fakes.dart';

const fast = LiveTimings(
  settleAfter: Duration(milliseconds: 80),
  tick: Duration(milliseconds: 20),
  drainMinWait: Duration(milliseconds: 30),
  drainQuiet: Duration(milliseconds: 40),
  drainMaxWait: Duration(milliseconds: 400),
);

void main() {
  late Directory tmp;
  late FakeTranslateBackend backend;
  late FakeMic mic;
  late FakeSpeaker speaker;
  late LibraryStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('scoai_voice_reply');
    backend = FakeTranslateBackend();
    mic = FakeMic();
    speaker = FakeSpeaker();
    store = LibraryStore(Directory('${tmp.path}/library'));
  });
  tearDown(() => tmp.delete(recursive: true));

  MeetingController make({TextAi? ai, bool readAloud = false}) => MeetingController(
        opener: backend.open,
        mic: mic,
        speaker: speaker,
        store: store,
        target: Lang.vi,
        readAloud: readAloud,
        textAi: ai,
        timings: fast,
      );

  test('Hỏi nhanh answers from the meeting so far and is saved with it', () async {
    final requests = <Map<String, Object?>>[];
    final ai = TextAi(ResponsesClient(
      key: () async => 'sk-x',
      httpClient: MockClient((req) async {
        requests.add((jsonDecode(req.body) as Map).cast<String, Object?>());
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': jsonEncode({'answer': '2,35 USD.', 'refs': ['00:00']})},
                ],
              },
            ],
          })),
          200,
        );
      }),
    ));
    final c = make(ai: ai);
    await c.start();
    backend.last.source('单价两块三五。', 0);
    backend.last.translation('Đơn giá 2,35. ');
    await waitFor(() => c.sentences.isNotEmpty);

    final qa = await c.ask('Giá bao nhiêu?');
    expect(qa.answer, '2,35 USD.');
    expect(c.liveQa.single.refs, ['00:00']);
    expect(requests.single['input'], contains('[00:00] 单价两块三五。 || Đơn giá 2,35.'));
    expect(requests.single['input'], endsWith('QUESTION:\nGiá bao nhiêu?'));

    final saved = await c.finish();
    expect((await store.get(saved!.id))!.qa.single.question, 'Giá bao nhiêu?');
  });
}

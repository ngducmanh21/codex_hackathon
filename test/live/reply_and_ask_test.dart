import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/live/meeting_controller.dart';
import 'package:scoai_voice_openai/openai/realtime_translate.dart';
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

/// Bytes of real speech (FakeMic.speak fills with 7) vs silence (0).
bool isSilence(FakeWs ws, int fromChunk) {
  final chunks = ws.ofType('session.input_audio_buffer.append').skip(fromChunk);
  return chunks.isNotEmpty && chunks.every((c) => base64Decode(c['audio'] as String).every((b) => b == 0));
}

void main() {
  late Directory tmp;
  late FakeTranslateBackend backend;
  late FakeMic mic;
  late FakeSpeaker speaker;
  late FakeSpeaker room;
  late LibraryStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('scoai_voice_reply');
    backend = FakeTranslateBackend();
    mic = FakeMic();
    speaker = FakeSpeaker();
    room = FakeSpeaker();
    store = LibraryStore(Directory('${tmp.path}/library'));
  });
  tearDown(() => tmp.delete(recursive: true));

  MeetingController make({TextAi? ai, bool readAloud = false}) => MeetingController(
        opener: backend.open,
        mic: mic,
        speaker: speaker,
        roomSpeaker: room,
        store: store,
        target: Lang.vi,
        readAloud: readAloud,
        textAi: ai,
        timings: fast,
      );

  group('Tôi trả lời', () {
    test('the reply goes to its own session; the meeting hears silence meanwhile', () async {
      final c = make();
      await c.start();
      final main = backend.last;
      mic.speak(200);
      await waitFor(() => main.audioBytes == 200 * 48);
      final mainChunksBefore = main.ofType('session.input_audio_buffer.append').length;

      await c.startReply();
      expect(c.replying, isTrue);
      final replyWs = backend.last;
      expect(backend.configs.last.target, Lang.zh, reason: 'nobody spoke yet: Vietnamese meeting replies in Chinese');
      expect(backend.configs.last.noise, NoiseReduction.nearField);

      mic.speak(400);
      await waitFor(() => replyWs.audioBytes >= 400 * 48);
      expect(isSilence(replyWs, 0), isFalse, reason: 'the reply session hears the user');
      await waitFor(() => main.audioBytes >= 600 * 48);
      expect(isSilence(main, mainChunksBefore), isTrue, reason: 'the meeting session hears silence');

      replyWs.source('Giá này được, ');
      replyWs.translation('这个价格可以，');
      replyWs.audio([9, 9, 9, 9]);
      await waitFor(() => c.reply!.translation.isNotEmpty);
      await settleAsync();
      expect(room.played, isEmpty, reason: 'held while the microphone is on the user');

      await c.endReply();
      expect(room.played.single, [9, 9, 9, 9], reason: 'the room hears it on the loudspeaker');
      expect(speaker.played, isEmpty, reason: 'not in the user\'s headphones');
      expect(replyWs.ofType('session.close'), hasLength(1));
      expect(c.reply, isNull);
      final mine = c.sentences.single;
      expect(mine.speaker, 0);
      expect(mine.source, 'Giá này được,');
      expect(mine.translation, '这个价格可以，');
      expect(mine.lang, Lang.vi);
      expect(mine.at, const Duration(milliseconds: 200));
      await c.discard();
    });

    test('speech played by the phone is not sent to the meeting session', () async {
      final c = make();
      await c.start();
      final main = backend.last;
      await c.startReply();
      final replyWs = backend.last;
      final ending = c.endReply();
      // A second of translated speech arrives while the reply session
      // finishes, after the user stopped talking.
      replyWs.audio(List.filled(48000, 1));
      await waitFor(() => room.played.isNotEmpty);
      final before = main.ofType('session.input_audio_buffer.append').length;
      mic.speak(400);
      await waitFor(() => main.ofType('session.input_audio_buffer.append').length >= before + 2);
      expect(isSilence(main, before), isTrue);
      await ending;
      await c.discard();
    });

    test('reply language follows the language heard most, or the user choice', () async {
      final c = make();
      await c.start();
      final main = backend.last;
      main.source('We agree. ', 0);
      main.translation('Chúng tôi đồng ý. ');
      main.source('Ship it. ', 900);
      main.translation('Giao đi. ');
      main.source('好的。', 1800);
      main.translation('Được. ');
      await waitFor(() => c.sentences.length == 3);
      expect(c.replyLang, Lang.en);
      c.setReplyLang(Lang.zh);
      expect(c.replyLang, Lang.zh);
      c.setReplyLang(null);
      expect(c.replyLang, Lang.en);
      await c.discard();
    });

    test('meeting read-aloud stays quiet while the user replies', () async {
      final c = make(readAloud: true);
      await c.start();
      final main = backend.last;
      await c.startReply();
      main.audio([1, 2]);
      await settleAsync();
      expect(speaker.played, isEmpty);
      await c.endReply();
      main.audio([3, 4]);
      await waitFor(() => speaker.played.isNotEmpty);
      expect(speaker.played.last, [3, 4]);
      await c.discard();
    });

    test('pausing ends a reply first', () async {
      final c = make();
      await c.start();
      await c.startReply();
      backend.last.source('Chờ chút. ');
      await settleAsync();
      await c.pause();
      expect(c.reply, isNull);
      expect(c.sentences.single.speaker, 0);
      await c.discard();
    });
  });

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

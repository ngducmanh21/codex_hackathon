import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/domain/records.dart';
import 'package:scoai_voice_openai/live/meeting_controller.dart';
import 'package:scoai_voice_openai/openai/responses_client.dart';
import 'package:scoai_voice_openai/openai/text_ai.dart';
import 'package:scoai_voice_openai/storage/library_store.dart';

import '../fakes.dart';

const fast = LiveTimings(
  settleAfter: Duration(milliseconds: 80),
  tick: Duration(milliseconds: 20),
  reconnectDelays: [Duration(milliseconds: 10), Duration(milliseconds: 10)],
  drainMinWait: Duration(milliseconds: 30),
  drainQuiet: Duration(milliseconds: 40),
  drainMaxWait: Duration(milliseconds: 400),
);

void main() {
  late Directory tmp;
  late LibraryStore store;
  late FakeTranslateBackend backend;
  late FakeMic mic;
  late FakeSpeaker speaker;
  final billed = <Duration>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('scoai_voice_test');
    store = LibraryStore(Directory('${tmp.path}/library'));
    backend = FakeTranslateBackend();
    mic = FakeMic();
    speaker = FakeSpeaker();
    billed.clear();
  });

  tearDown(() => tmp.delete(recursive: true));

  MeetingController make({
    bool readAloud = false,
    TextAi? textAi,
    MeetingContext context = const MeetingContext(),
    LiveTimings timings = fast,
  }) =>
      MeetingController(
        opener: backend.open,
        mic: mic,
        speaker: speaker,
        store: store,
        target: Lang.vi,
        title: 'Họp thử',
        context: context,
        readAloud: readAloud,
        textAi: textAi,
        timings: timings,
        onAudioBilled: billed.add,
      );

  test('streams the microphone and turns deltas into bilingual sentences', () async {
    final c = make();
    await c.start();
    expect(c.state, LiveState.live);
    expect(backend.configs.single.target, Lang.vi);

    mic.speak(400);
    await waitFor(() => backend.last.audioBytes == 400 * 48);
    expect(c.recorded, const Duration(milliseconds: 400));

    backend.last.source('如果订单超过五百件，', 0);
    backend.last.source('我们可以降价。', 900);
    backend.last.translation('Nếu đơn trên 500 chiếc, ');
    await waitFor(() => c.liveTranslation.isNotEmpty);
    expect(c.sentences, isEmpty);
    expect(c.liveSource, '如果订单超过五百件，我们可以降价。');

    backend.last.translation('chúng tôi có thể giảm giá. ');
    await waitFor(() => c.sentences.isNotEmpty);
    expect(c.sentences.single.translation, 'Nếu đơn trên 500 chiếc, chúng tôi có thể giảm giá.');
    await c.discard();
  });

  test('read-aloud plays translated audio only while switched on', () async {
    final c = make();
    await c.start();
    backend.last.audio([1, 2, 3, 4]);
    await settleAsync();
    expect(speaker.played, isEmpty);
    c.setReadAloud(true);
    backend.last.audio([5, 6]);
    await waitFor(() => speaker.played.isNotEmpty);
    expect(speaker.played.single, [5, 6]);
    c.setReadAloud(false);
    expect(speaker.stops, greaterThan(0), reason: 'switching off drops queued speech');
    await c.discard();
  });

  test('a pause in speech settles pending text into a sentence', () async {
    final c = make();
    await c.start();
    backend.last.source('嗯，好的', 0);
    await waitFor(() => c.liveSource.isNotEmpty);
    await waitFor(() => c.sentences.isNotEmpty);
    expect(c.sentences.single.source, '嗯，好的');
    expect(c.liveSource, isEmpty);
    await c.discard();
  });

  test('pause drains and closes the session; resume opens a new one timed after it', () async {
    final c = make();
    await c.start();
    mic.speak(1000);
    await waitFor(() => backend.last.audioBytes == 1000 * 48);
    final first = backend.last;

    await c.pause();
    expect(c.state, LiveState.paused);
    expect(mic.running, isFalse);
    expect(first.ofType('session.close'), hasLength(1));
    expect(first.audioBytes, greaterThan(1000 * 48), reason: 'silence is sent so the model can finish');
    expect(billed, isNotEmpty);

    await c.resume();
    expect(c.state, LiveState.live);
    expect(backend.servers, hasLength(2));
    backend.last.source('第二段。', 200);
    backend.last.translation('Đoạn hai. ');
    await waitFor(() => c.sentences.isNotEmpty);
    expect(c.sentences.single.at, const Duration(milliseconds: 1200));
    await c.discard();
  });

  test('finish saves the meeting to the Library', () async {
    final c = make();
    await c.start();
    backend.last.source('价格可以。', 0);
    backend.last.translation('Giá được. ');
    await waitFor(() => c.sentences.isNotEmpty);
    final item = await c.finish();

    expect(c.state, LiveState.finished);
    expect(item, isNotNull);
    final loaded = await store.get(item!.id);
    expect(loaded!.title, 'Họp thử');
    expect(loaded.kind, ItemKind.meeting);
    expect(loaded.targetLang, Lang.vi);
    expect(loaded.sentences.single.translation, 'Giá được.');
  });

  test('finish with nothing heard saves nothing', () async {
    final c = make();
    await c.start();
    expect(await c.finish(), isNull);
    expect(await store.list(), isEmpty);
  });

  test('reconnects after a dropped connection and sends the buffered audio', () async {
    final c = make(
      timings: const LiveTimings(
        settleAfter: Duration(milliseconds: 80),
        tick: Duration(milliseconds: 20),
        reconnectDelays: [Duration(milliseconds: 80)],
      ),
    );
    await c.start();
    final first = backend.last;
    await first.drop();
    // Speak while disconnected: the audio must wait for the new session.
    await settleAsync(15);
    mic.speak(200);
    await settleAsync(5);
    expect(backend.servers, hasLength(1));
    expect(first.audioBytes, 0);
    await waitFor(() => backend.servers.length == 2);
    final second = backend.last;
    await waitFor(() => second.audioBytes >= 200 * 48);
    expect(c.state, LiveState.live);
    mic.speak(200);
    await waitFor(() => second.audioBytes >= 400 * 48);
    await c.discard();
  });

  test('gives up after repeated connection failures and pauses', () async {
    final c = make();
    await c.start();
    backend.failNext = 5;
    await backend.last.drop();
    await waitFor(() => c.state == LiveState.paused);
    expect(c.notice, contains('Không nối lại được'));
    await c.discard();
  });

  test('rolls over to a fresh session before the session limit', () async {
    final c = make(
      timings: const LiveTimings(
        settleAfter: Duration(milliseconds: 80),
        tick: Duration(milliseconds: 20),
        rolloverAt: Duration(milliseconds: 600),
        drainMinWait: Duration(milliseconds: 20),
        drainQuiet: Duration(milliseconds: 20),
        drainMaxWait: Duration(milliseconds: 200),
      ),
    );
    await c.start();
    mic.speak(800);
    await waitFor(() => backend.servers.length == 2);
    expect(backend.servers.first.ofType('session.close'), hasLength(1));
    mic.speak(200);
    await waitFor(() => backend.last.audioBytes >= 200 * 48);
    expect(c.state, LiveState.live);
    await c.discard();
  });

  test('changing "Dịch sang" updates the open session', () async {
    final c = make();
    await c.start();
    c.setTarget(Lang.en);
    expect(c.target, Lang.en);
    expect(backend.last.sent.last['session'], {
      'audio': {
        'output': {'language': 'en'},
      },
    });
    await c.discard();
  });

  test('sentences with a glossary term are re-translated with the glossary', () async {
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
                  {'type': 'output_text', 'text': jsonEncode({'translations': ['Tuần sau bắt đầu dán SMT.']})},
                ],
              },
            ],
          })),
          200,
        );
      }),
    ));
    final c = make(textAi: ai, context: const MeetingContext(terms: [Term('贴片', 'dán SMT')]));
    await c.start();
    backend.last.source('贴片下周开始。', 0);
    backend.last.translation('Tuần sau bắt đầu dán chip. ');
    await waitFor(() => c.sentences.isNotEmpty);
    await waitFor(() => c.sentences.single.translation == 'Tuần sau bắt đầu dán SMT.');
    expect(requests.single['instructions'], contains('贴片 => dán SMT'));
    expect(jsonDecode(requests.single['input'] as String), {
      'segments': ['贴片下周开始。'],
    });
    await c.discard();
  });

  test('leaving while still connecting closes the late session', () async {
    final gate = Completer<void>();
    final slow = MeetingController(
      opener: (cfg) async {
        await gate.future;
        return backend.open(cfg);
      },
      mic: mic,
      speaker: speaker,
      store: store,
      target: Lang.vi,
      timings: fast,
    );
    final starting = slow.start();
    await settleAsync();
    await slow.discard();
    gate.complete();
    await starting;
    await waitFor(() => backend.servers.isNotEmpty && backend.last.closedByClient);
    expect(backend.last.ofType('session.close'), hasLength(1));
    expect(mic.running, isFalse);
  });

  test('no microphone permission fails without opening a session', () async {
    mic.permission = false;
    final c = make();
    await c.start();
    expect(c.state, LiveState.failed);
    expect(backend.servers, isEmpty);
    expect(c.notice, contains('micro'));
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scoai_voice_openai/app/services.dart';
import 'package:scoai_voice_openai/demo/demo_http.dart';
import 'package:scoai_voice_openai/demo/demo_library.dart';
import 'package:scoai_voice_openai/demo/demo_script.dart';
import 'package:scoai_voice_openai/demo/demo_translate.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/domain/records.dart';
import 'package:scoai_voice_openai/domain/segmenter.dart';
import 'package:scoai_voice_openai/live/meeting_controller.dart';
import 'package:scoai_voice_openai/openai/responses_client.dart';
import 'package:scoai_voice_openai/openai/text_ai.dart';
import 'package:scoai_voice_openai/storage/key_store.dart';
import 'package:scoai_voice_openai/storage/library_store.dart';
import 'package:scoai_voice_openai/storage/settings_store.dart';

import '../fakes.dart';

const fast = LiveTimings(
  settleAfter: Duration(milliseconds: 120),
  tick: Duration(milliseconds: 20),
  drainMinWait: Duration(milliseconds: 30),
  drainQuiet: Duration(milliseconds: 60),
  drainMaxWait: Duration(milliseconds: 600),
);

void main() {
  late Directory tmp;
  late LibraryStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('scoai_voice_demo');
    store = LibraryStore(Directory('${tmp.path}/library'));
  });
  tearDown(() => tmp.delete(recursive: true));

  group('scripted meeting', () {
    late FakeMic mic;
    late FakeSpeaker speaker;
    late MeetingController c;

    setUp(() {
      mic = FakeMic();
      speaker = FakeSpeaker();
      c = MeetingController(
        opener: demoOpener(speed: 0.03),
        mic: mic,
        speaker: speaker,
        store: store,
        target: Lang.vi,
        readAloud: true,
        timings: fast,
      );
    });

    test('plays the sample meeting as bilingual captions through the real client', () async {
      await c.start();
      await waitFor(() => c.sentences.length >= 4, timeout: const Duration(seconds: 8));
      final first = c.sentences.first;
      expect(first.source, demoMeeting[0].zh);
      expect(first.translation, demoMeeting[0].vi);
      expect(first.lang, Lang.zh);
      final vietnamese = c.sentences.firstWhere((s) => s.lang == Lang.vi);
      expect(vietnamese.source, demoMeeting[2].vi);
      expect(vietnamese.hasTranslation, isFalse, reason: 'already in the target language');
      expect(speaker.played, isNotEmpty, reason: 'read-aloud gets the sample speech');
      await c.discard();
    });

  });

  group('sample text AI', () {
    final ai = TextAi(ResponsesClient(key: () async => 'demo', httpClient: demoHttpClient(delay: Duration.zero)));
    final meeting = demoLibraryItems(DateTime(2026, 11, 13)).first;

    test('summary, quick question with its line, explanation and photo context', () async {
      final s = await ai.summarize(meeting, readingLang: Lang.vi);
      expect(s.decisions, isNotEmpty);
      expect(s.actions.first.task, contains('BOM'));

      final qa = await ai.ask(meeting, 'Giá bao nhiêu?');
      expect(qa.answer, contains('2,35'));
      expect(qa.refs, [formatClock(meeting.sentences[3].at)]);

      final x = await ai.explain(meeting.sentences[3], readingLang: Lang.vi);
      expect(x.meaning, contains(demoMeeting[3].vi));
      expect(guessLang(x.replies.first.text), Lang.zh);

      final ctx = await ai.contextFromImage(Uint8List(3), mimeType: 'image/jpeg', target: Lang.vi);
      expect(ctx.terms.map((t) => t.source), contains('MOQ'));
    });

    test('translation knows the sample lines and marks others as samples', () async {
      final out = await ai.translate([demoMeeting[4].en, 'Something else.'], to: Lang.vi);
      expect(out.first, demoMeeting[4].vi);
      expect(out.last, startsWith('(bản dịch mẫu)'));
    });
  });

  test('turning demo mode on seeds the Library and needs no key; off removes the samples', () async {
    final settings = SettingsStore(File('${tmp.path}/settings.json'));
    final real = FakeTranslateBackend();
    final s = AppServices(
      keys: MemoryKeyStore(),
      settings: settings,
      library: store,
      newMic: FakeMic.new,
      speaker: FakeSpeaker(),
      opener: real.open,
    );
    expect(await s.hasKey(), isFalse);
    expect(s.opener, same(s.opener));
    final realOpener = s.opener;

    await s.setDemoMode(true);
    expect(await s.hasKey(), isTrue);
    expect(s.opener, isNot(same(realOpener)));
    expect(s.onAudioBilled, isNull, reason: 'nothing is billed in demo mode');
    expect((await store.list()).map((i) => i.id), everyElement(startsWith(demoIdPrefix)));
    expect(await store.list(), hasLength(2));

    final mine = LibraryItem.fromJson(demoLibraryItems(DateTime(2026)).first.toJson()..['id'] = 'mine-1');
    await store.save(mine);
    await s.setDemoMode(false);
    expect((await store.list()).map((i) => i.id), ['mine-1'], reason: 'only samples are removed');
    expect(s.opener, same(realOpener));

    final reloaded = SettingsStore(File('${tmp.path}/settings.json'));
    await reloaded.load();
    expect(reloaded.demoMode, isFalse);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoai_voice_openai/app/services.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/domain/records.dart';
import 'package:scoai_voice_openai/live/meeting_controller.dart';
import 'package:scoai_voice_openai/storage/key_store.dart';
import 'package:scoai_voice_openai/storage/library_store.dart';
import 'package:scoai_voice_openai/storage/settings_store.dart';
import 'package:scoai_voice_openai/ui/captions.dart';
import 'package:scoai_voice_openai/ui/meeting_screen.dart';
import 'package:scoai_voice_openai/ui/theme.dart';

import '../fakes.dart';

Finder rich(String text) => find.textContaining(text, findRichText: true);

void main() {
  group('MeetingCaption', () {
    Future<void> show(WidgetTester tester, Sentence s, CaptionView view) => tester.pumpWidget(
          MaterialApp(theme: buildTheme(), home: Scaffold(body: MeetingCaption(sentence: s, view: view, onMark: () {}))),
        );

    const zh = Sentence(at: Duration.zero, source: '我们可以降价。', translation: 'Chúng tôi có thể giảm giá.', lang: Lang.zh);

    testWidgets('Cả hai: tagged original small, translation large', (tester) async {
      await show(tester, zh, CaptionView.both);
      expect(rich('Trung'), findsOneWidget);
      expect(rich('我们可以降价。'), findsOneWidget);
      final big = tester.widget<Text>(find.byKey(const Key('caption-big')));
      expect(big.data, 'Chúng tôi có thể giảm giá.');
      expect(big.style!.fontSize, 20);
    });

    testWidgets('Gốc shows only the words as spoken, Dịch only the translation', (tester) async {
      await show(tester, zh, CaptionView.original);
      expect(rich('我们可以降价。'), findsOneWidget);
      expect(rich('Chúng tôi có thể'), findsNothing);
      await show(tester, zh, CaptionView.translation);
      expect(rich('Chúng tôi có thể giảm giá.'), findsOneWidget);
      expect(rich('我们'), findsNothing);
    });

    testWidgets('a sentence already in the target language is one line, with no "no translation" label', (tester) async {
      await show(tester, const Sentence(at: Duration.zero, source: 'Giá còn hơi cao.', translation: '', lang: Lang.vi), CaptionView.both);
      expect(find.byKey(const Key('caption-small')), findsNothing);
      expect(rich('Giá còn hơi cao.'), findsOneWidget);
      expect(rich('Việt'), findsOneWidget);
      expect(find.textContaining('Chưa có bản dịch'), findsNothing);
    });
  });

  testWidgets('pending text says "Đang dịch…" only when a translation is expected', (tester) async {
    Future<void> pending(String source) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: PendingCaption(source: source, translation: '', target: Lang.vi, view: CaptionView.both),
          ),
        ));
    await pending('And the lead time');
    expect(find.byKey(const Key('caption-pending')), findsOneWidget);
    await pending('Còn thời gian giao hàng');
    expect(find.byKey(const Key('caption-pending')), findsNothing);
  });

  group('MeetingScreen', () {
    late FakeTranslateBackend backend;
    late MeetingController c;

    Future<void> open(WidgetTester tester) async {
      backend = FakeTranslateBackend();
      final mic = FakeMic();
      final services = AppServices(
        keys: MemoryKeyStore('sk-test'),
        settings: SettingsStore(File('${Directory.systemTemp.path}/scoai_voice_unused/settings.json')),
        library: LibraryStore(Directory('${Directory.systemTemp.path}/scoai_voice_unused/library')),
        newMic: () => mic,
        speaker: FakeSpeaker(),
        opener: backend.open,
      );
      c = MeetingController(
        opener: backend.open,
        mic: mic,
        speaker: FakeSpeaker(),
        store: services.library,
        target: Lang.vi,
        timings: const LiveTimings(settleAfter: Duration(seconds: 30)),
      );
      await tester.pumpWidget(Services(
        services: services,
        child: MaterialApp(
          theme: buildTheme(),
          home: MeetingScreen(
            title: '',
            target: Lang.vi,
            readAloud: false,
            meetingContext: const MeetingContext(),
            controller: c,
          ),
        ),
      ));
      for (var i = 0; i < 5 && c.state != LiveState.live; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(c.state, LiveState.live);
      await tester.pump();
    }

    Future<void> close(WidgetTester tester) async {
      // Stopping awaits plugin-style futures that only complete on the real
      // event loop, so run it outside the fake clock.
      await tester.runAsync(() => c.discard());
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }

    testWidgets('only "Đang nghe…" before the first sentence, then bilingual captions', (tester) async {
      await open(tester);
      expect(find.text('Đang nghe…'), findsOneWidget);
      expect(find.text('Đang ghi · 00:00'), findsOneWidget, reason: 'the status capsule');
      expect(find.byKey(const Key('languages')), findsOneWidget, reason: 'languages can be set before anyone speaks');

      backend.last.source('这次的样品看过了吧？', 0);
      backend.last.translation('Mọi người đã xem mẫu chưa? ');
      backend.last.source('如果订单超过五百件', 900);
      await tester.pump();
      await tester.pump();

      expect(find.text('Mọi người đã xem mẫu chưa?'), findsOneWidget);
      expect(rich('这次的样品看过了吧？'), findsOneWidget);
      expect(find.byKey(const Key('caption-pending')), findsOneWidget);
      expect(find.text('Đang nghe…'), findsOneWidget);

      await tester.tap(find.byKey(const Key('view-original')));
      await tester.pump();
      expect(find.text('Mọi người đã xem mẫu chưa?'), findsNothing);

      await tester.tap(find.byTooltip('Đánh dấu').first);
      await tester.pump();
      expect(c.sentences.first.marked, isTrue);

      await tester.tap(find.byKey(const Key('read-aloud')));
      await tester.pump();
      expect(c.readAloud, isTrue);
      await close(tester);
    });

    testWidgets('"Phát biểu" opens a reply session and shows what the user says', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('reply-banner')), findsNothing);
      await tester.tap(find.byKey(const Key('reply')));
      await tester.pump();
      await tester.pump();
      expect(backend.servers, hasLength(2));
      expect(backend.configs.last.target, Lang.zh);
      expect(find.byKey(const Key('reply-banner')), findsOneWidget);
      backend.last.source('Giá này được.');
      backend.last.translation('这个价格可以。');
      await tester.pump();
      await tester.pump();
      expect(find.text('这个价格可以。'), findsOneWidget);
      expect(find.textContaining('Bạn đang phát biểu → tiếng Trung'), findsOneWidget);
      expect(find.text('Xong'), findsOneWidget);
      await close(tester);
    });

    testWidgets('the language pill sets captions and "Phát biểu" languages', (tester) async {
      await open(tester);
      expect(find.text('Phát biểu'), findsOneWidget);
      await tester.tap(find.byKey(const Key('languages')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Tự động (Trung)'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const Key('lang-speak')), matching: find.text('Tiếng Anh')));
      await tester.pump();
      expect(c.replyLang, Lang.en);
      expect(c.replyLangChoice, Lang.en);
      await tester.tap(find.descendant(of: find.byKey(const Key('lang-target')), matching: find.text('Tiếng Trung')));
      await tester.pump();
      expect(c.target, Lang.zh);
      expect(backend.servers.first.sent.last['session'], {
        'audio': {
          'output': {'language': 'zh'},
        },
      });
      await close(tester);
    });

    testWidgets('the language filter keeps only sentences spoken in that language', (tester) async {
      await open(tester);
      backend.last.source('We agree. ', 0);
      backend.last.translation('Chúng tôi đồng ý. ');
      backend.last.source('好的。', 500);
      backend.last.translation('Được. ');
      await tester.pump();
      await tester.pump();
      expect(c.sentences, hasLength(2));

      // The filter lives in the language sheet. The sheet opens with an
      // animation and "Đang nghe…" pulses forever, so pump a fixed time.
      await tester.tap(find.byKey(const Key('languages')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.descendant(of: find.byKey(const Key('lang-filter')), matching: find.text('Tiếng Trung')));
      await tester.pump();
      await tester.tapAt(const Offset(10, 10)); // close the sheet
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Được.'), findsOneWidget);
      expect(find.text('Chúng tôi đồng ý.'), findsNothing);
      expect(find.byKey(const Key('filter-badge')), findsOneWidget, reason: 'the pill shows the filter');
      await close(tester);
    });
  });
}

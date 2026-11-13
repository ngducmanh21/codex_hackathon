import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/live/meeting_controller.dart';
import 'package:scoai_voice_openai/storage/library_store.dart';

import '../fakes.dart';

const fast = LiveTimings(
  settleAfter: Duration(milliseconds: 80),
  tick: Duration(milliseconds: 20),
  drainMinWait: Duration(milliseconds: 20),
  drainQuiet: Duration(milliseconds: 30),
  drainMaxWait: Duration(milliseconds: 300),
);

void main() {
  late Directory tmp;
  late FakeTranslateBackend backend;
  late FakeMic mic;
  late FakeBackground background;
  late MeetingController c;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('scoai_voice_bg');
    backend = FakeTranslateBackend();
    mic = FakeMic();
    background = FakeBackground();
    c = MeetingController(
      opener: backend.open,
      mic: mic,
      speaker: FakeSpeaker(),
      store: LibraryStore(Directory('${tmp.path}/library')),
      target: Lang.vi,
      title: 'Họp nhà cung cấp',
      background: background,
      timings: fast,
    );
  });
  tearDown(() async {
    c.dispose();
    await tmp.delete(recursive: true);
  });

  test('the service runs only while the meeting records, and shows its clock', () async {
    expect(background.running, isFalse);

    await c.start();
    expect(background.calls.first, 'start');
    expect(background.running, isTrue);
    expect(background.title, 'Họp nhà cung cấp');
    expect(background.text, 'Đang ghi · 00:00');

    // A second of audio moves the clock, and the notification follows.
    mic.speak(1000);
    await waitFor(() => background.text == 'Đang ghi · 00:01');
    expect(background.calls.contains('update'), isTrue);

    await c.pause();
    expect(background.running, isFalse, reason: 'a paused meeting holds no microphone');

    await c.resume();
    expect(background.running, isTrue);

    await c.finish();
    expect(background.running, isFalse);
  });

  test('an unnamed meeting still names the notification', () async {
    final plain = MeetingController(
      opener: backend.open,
      mic: mic,
      speaker: FakeSpeaker(),
      store: LibraryStore(Directory('${tmp.path}/library2')),
      target: Lang.vi,
      background: background,
      timings: fast,
    );
    await plain.start();
    expect(background.title, 'Cuộc họp');
    await plain.discard();
    expect(background.running, isFalse);
    plain.dispose();
  });

  test('discarding a meeting stops the service', () async {
    await c.start();
    expect(background.running, isTrue);
    await c.discard();
    expect(background.calls.last, 'stop');
  });
}

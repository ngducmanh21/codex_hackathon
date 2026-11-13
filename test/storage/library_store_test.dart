import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/domain/records.dart';
import 'package:scoai_voice_openai/storage/key_store.dart';
import 'package:scoai_voice_openai/storage/library_store.dart';
import 'package:scoai_voice_openai/storage/settings_store.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('scoai_voice_store'));
  tearDown(() => tmp.delete(recursive: true));

  LibraryItem item(String id, DateTime at) => LibraryItem(
        id: id,
        kind: ItemKind.upload,
        title: 'Tệp $id',
        createdAt: at,
        duration: const Duration(minutes: 3),
        sourceLang: Lang.en,
        targetLang: Lang.vi,
        context: const MeetingContext(topic: 'Sales', terms: [Term('MOQ', 'số lượng tối thiểu')]),
        sentences: const [Sentence(at: Duration.zero, source: 'Hello.', translation: 'Xin chào.', lang: Lang.en)],
        summary: const Summary(overview: 'Ngắn', actions: [ActionItem(task: 'Gọi lại')]),
        qa: const [QaPair(question: 'Ai?', answer: 'Anh Nam', refs: ['#1'])],
      );

  test('round-trips items, newest first, and skips corrupt files', () async {
    final store = LibraryStore(Directory('${tmp.path}/lib'));
    await store.save(item('a', DateTime(2026, 11, 1)));
    await store.save(item('b', DateTime(2026, 11, 12)));
    await File('${tmp.path}/lib/broken.json').writeAsString('{not json');

    final list = await store.list();
    expect(list.map((i) => i.id), ['b', 'a']);
    final b = (await store.get('b'))!;
    expect(b.context.terms.single, const Term('MOQ', 'số lượng tối thiểu'));
    expect(b.summary!.actions.single.task, 'Gọi lại');
    expect(b.qa.single.refs, ['#1']);
    expect(b.sentences.single.lang, Lang.en);

    await store.delete('a');
    expect((await store.list()).map((i) => i.id), ['b']);
  });

  test('rejects ids that could escape the folder', () {
    final store = LibraryStore(Directory('${tmp.path}/lib'));
    expect(() => store.get('../x'), throwsArgumentError);
  });

  test('new ids are file-name safe', () {
    expect(newItemId(DateTime.utc(2026, 11, 13, 5, 20)), matches(RegExp(r'^20261113052000-[a-z0-9]+$')));
  });

  test('usage adds up to a cost estimate and survives reload', () async {
    final f = File('${tmp.path}/settings.json');
    final s = SettingsStore(f)
      ..addTranslateAudio(const Duration(minutes: 60))
      ..addTokens('gpt-6-luna-2026-10-01', 1000000, 100000)
      ..addTranscribeSeconds(600);
    await s.save();
    final u = s.usageFor(DateTime.now());
    // 60 min × 0.034 + 1M × 0.10 + 0.1M × 0.50 + 10 min × 0.0045
    expect(u.dollars, closeTo(2.04 + 0.10 + 0.05 + 0.045, 1e-9));

    final again = SettingsStore(f);
    await again.load();
    expect(again.usageFor(DateTime.now()).dollars, closeTo(u.dollars, 1e-9));
  });

  test('the masked key shows only its ends', () {
    expect(maskKey('sk-proj-abcdefghijklmnop1234'), 'sk-…1234');
    expect(maskKey('short'), '••••');
  });
}

import '../domain/lang.dart';
import '../domain/records.dart';
import '../storage/library_store.dart';
import 'demo_script.dart';

/// Saved items that come with "Chế độ thử"; their ids start with this.
const demoIdPrefix = 'demo-';

/// A finished meeting (summary, Q&A, a bookmark, one "Phát biểu" line) and
/// an uploaded file without a summary yet, to try every Library screen.
List<LibraryItem> demoLibraryItems(DateTime now) {
  const context = MeetingContext(
    topic: 'Đàm phán đơn hàng linh kiện điện tử với nhà cung cấp ở Thâm Quyến.',
    terms: [Term('MOQ', 'số lượng đặt tối thiểu'), Term('贴片', 'dán linh kiện SMT'), Term('BOM', 'danh mục vật tư')],
  );
  final sentences = <Sentence>[
    for (var i = 0; i < demoMeeting.length; i++)
      Sentence(
        at: Duration(seconds: 20 + i * 38),
        source: demoMeeting[i].said,
        translation: demoMeeting[i].spoken == Lang.vi ? '' : demoMeeting[i].vi,
        lang: demoMeeting[i].spoken,
        marked: i == 3,
      ),
    Sentence(
      at: Duration(seconds: 20 + demoMeeting.length * 38),
      source: demoReply.vi,
      translation: demoReply.zh,
      lang: Lang.vi,
      speaker: 0,
    ),
  ];
  final meeting = LibraryItem(
    id: '${demoIdPrefix}meeting-1',
    kind: ItemKind.meeting,
    title: '[Mẫu] Họp nhà cung cấp Thâm Quyến',
    createdAt: now.subtract(const Duration(days: 1)),
    duration: const Duration(minutes: 6, seconds: 12),
    targetLang: Lang.vi,
    context: context,
    sentences: sentences,
    summary: const Summary(
      overview:
          'Hai bên xem mẫu linh kiện. Bên mình thấy chất lượng ổn nhưng giá cao; nhà cung cấp đề nghị 2,35 USD/chiếc cho đơn từ 500 chiếc và có thể dán SMT từ tuần sau.',
      decisions: ['Đơn giá 2,35 USD/chiếc khi đặt từ 500 chiếc.', 'MOQ 500 chiếc.'],
      actions: [
        ActionItem(task: 'Gửi BOM mới nhất cho nhà cung cấp', owner: 'Bên mình', due: 'trước thứ Sáu'),
        ActionItem(task: 'Bắt đầu dán SMT', owner: 'Nhà cung cấp', due: 'tuần sau'),
      ],
      openQuestions: ['Thời gian giao lô thứ hai chưa chốt ngày cụ thể.'],
    ),
    qa: [
      QaPair(
        question: 'Giá cuối cùng là bao nhiêu?',
        answer: 'Nhà cung cấp đề nghị 2,35 USD/chiếc nếu đơn hàng trên 500 chiếc; bên mình đồng ý nếu giao trước ngày 20.',
        refs: [formatClock(sentences[3].at), formatClock(sentences.last.at)],
      ),
    ],
  );
  final english = [for (final l in demoMeeting) if (l.spoken == Lang.en || l.spoken == Lang.zh) l].take(4).toList();
  final upload = LibraryItem(
    id: '${demoIdPrefix}upload-1',
    kind: ItemKind.upload,
    title: '[Mẫu] ghi-am-goi-dien.m4a',
    createdAt: now.subtract(const Duration(days: 2)),
    duration: const Duration(minutes: 2, seconds: 40),
    sourceLang: Lang.en,
    targetLang: Lang.vi,
    sentences: [
      for (final l in english) Sentence(at: Duration.zero, source: l.en, translation: l.vi, lang: Lang.en),
    ],
  );
  return [meeting, upload];
}

/// Adds the sample items that are missing.
Future<void> seedDemoLibrary(LibraryStore store, {DateTime? now}) async {
  for (final item in demoLibraryItems(now ?? DateTime.now())) {
    if (await store.get(item.id) == null) await store.save(item);
  }
}

/// Removes every sample item.
Future<void> clearDemoLibrary(LibraryStore store) async {
  for (final item in await store.list()) {
    if (item.id.startsWith(demoIdPrefix)) await store.delete(item.id);
  }
}

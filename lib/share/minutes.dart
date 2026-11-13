import '../domain/records.dart';

/// Meeting minutes as plain text for Zalo, Messenger or e-mail: the
/// summary first, then, when asked, the bilingual transcript.
String minutesText(LibraryItem item, {bool withTranscript = false}) {
  final b = StringBuffer();
  final t = item.createdAt;
  final when = '${_two(t.day)}/${_two(t.month)}/${t.year} ${_two(t.hour)}:${_two(t.minute)}';
  final langs = item.kind == ItemKind.dialogue
      ? '${item.sourceLang?.viTitle ?? ''} ⇄ ${item.targetLang.viTitle}'
      : 'Dịch sang ${item.targetLang.viName}';
  b
    ..writeln(item.title)
    ..writeln('$when · ${formatClock(item.duration)} · $langs');

  final s = item.summary;
  if (s != null) {
    b
      ..writeln()
      ..writeln('TÓM TẮT')
      ..writeln(s.overview.trim());
    _list(b, 'ĐÃ CHỐT', s.decisions);
    if (s.actions.isNotEmpty) {
      b
        ..writeln()
        ..writeln('VIỆC CẦN LÀM');
      for (final a in s.actions) {
        final who = [a.owner, a.due].where((x) => x.trim().isNotEmpty).join(' · ');
        b.writeln('- ${a.task.trim()}${who.isEmpty ? '' : ' ($who)'}');
      }
    }
    _list(b, 'CÒN BỎ NGỎ', s.openQuestions);
  }

  if (withTranscript || s == null) {
    b
      ..writeln()
      ..writeln('BẢN GHI');
    final times = item.kind != ItemKind.upload;
    for (var i = 0; i < item.sentences.length; i++) {
      final x = item.sentences[i];
      final label = times ? formatClock(x.at) : '#${i + 1}';
      final who = x.speaker == 0
          ? (item.kind == ItemKind.dialogue ? 'Tôi' : 'Bạn')
          : x.speaker == 1
              ? 'Người kia'
              : (x.lang?.short ?? '');
      b.writeln('[$label]${who.isEmpty ? '' : ' $who:'} ${x.source}');
      if (x.hasTranslation) b.writeln('    → ${x.translation}');
    }
  }
  b
    ..writeln()
    ..write('— Ghi bằng SCOAI Voice');
  return b.toString();
}

void _list(StringBuffer b, String title, List<String> items) {
  if (items.isEmpty) return;
  b
    ..writeln()
    ..writeln(title);
  for (final i in items) {
    b.writeln('- ${i.trim()}');
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

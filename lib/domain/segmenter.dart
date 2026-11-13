import 'lang.dart';

const _terminators = '.?!。？！…';

bool _isTerminator(String ch) => _terminators.contains(ch);

/// Characters that may follow a terminator and still belong to the sentence.
bool _isCloser(String ch) => '"\'”’)）」』'.contains(ch);

/// Splits [text] into whole sentences plus the unfinished rest.
///
/// A Latin full stop only ends a sentence when followed by whitespace, so
/// "2.35" and "v1.2" stay intact while the text is still streaming. CJK
/// terminators end a sentence immediately.
({List<String> sentences, String rest}) cutSentences(String text) {
  final out = <String>[];
  var start = 0;
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (_isTerminator(ch)) {
      var end = i + 1;
      while (end < text.length && (_isTerminator(text[end]) || _isCloser(text[end]))) {
        end++;
      }
      final cjk = '。？！'.contains(ch);
      final atEnd = end >= text.length;
      final followedBySpace = !atEnd && RegExp(r'\s').hasMatch(text[end]);
      if (cjk || followedBySpace) {
        final s = text.substring(start, end).trim();
        if (s.isNotEmpty) out.add(s);
        start = end;
        i = end;
        continue;
      }
      i = end;
      continue;
    }
    if (ch == '\n') {
      final s = text.substring(start, i).trim();
      if (s.isNotEmpty) out.add(s);
      start = i + 1;
    }
    i++;
  }
  return (sentences: out, rest: text.substring(start));
}

/// Splits finished text (for example a file transcript) into sentences.
List<String> splitSentences(String text) {
  final r = cutSentences(text);
  final rest = r.rest.trim();
  return [...r.sentences, if (rest.isNotEmpty) rest];
}

/// Best guess of the language of [text] from its script.
Lang? guessLang(String text) {
  var cjk = 0, viMarks = 0, latin = 0;
  for (final r in text.runes) {
    if ((r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF)) {
      cjk++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      latin++;
    } else if (_vietnameseOnly.contains(String.fromCharCode(r).toLowerCase())) {
      viMarks++;
      latin++;
    } else if (r >= 0xC0 && r <= 0x1EF9) {
      latin++;
    }
  }
  if (cjk == 0 && latin == 0) return null;
  if (cjk >= latin) return Lang.zh;
  return viMarks > 0 ? Lang.vi : Lang.en;
}

const _vietnameseOnly = 'ăâđêôơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ';

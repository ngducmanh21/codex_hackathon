import 'lang.dart';
import 'records.dart';
import 'segmenter.dart';

/// Turns the two append-only text streams of a translation session (what
/// was said, and its translation) into bilingual sentences.
///
/// The session gives no sentence boundaries and no ids linking a
/// translation to its source, so pairing is heuristic:
/// - both streams are cut at sentence punctuation;
/// - a source sentence already in the target language is committed on its
///   own (the model does not translate it);
/// - the other source sentences are paired in order with translated
///   sentences;
/// - at every pause ([settle]) whatever is left is folded into the last
///   sentence, so a mismatch never outlives one pause.
class CaptionAssembler {
  CaptionAssembler({required this.target, this.maxBacklog = 5});

  /// "Dịch sang"; may change during a meeting.
  Lang target;

  /// Pending source sentences allowed before they are merged into one
  /// block, which bounds memory when the speaker never pauses.
  final int maxBacklog;

  /// Start of the current session within the whole recording.
  Duration offset = Duration.zero;

  final List<Sentence> committed = [];

  final List<_Pending> _src = [];
  String _srcBuf = '';
  int? _srcBufStartMs;
  int _lastMs = 0;

  final List<String> _dst = [];
  String _dstBuf = '';

  /// Index in [committed] of sentences committed since the last pause that
  /// carry a translation; leftovers fold into the last of them.
  int? _lastPairedThisRound;

  /// Text recognised but not yet in a finished sentence.
  String get liveSource =>
      _join([for (final p in _src) p.text, _srcBuf.trim()]);

  /// Translation produced but not yet attached to a sentence.
  String get liveTranslation => _join([..._dst, _dstBuf.trim()]);

  bool get hasPending =>
      _src.isNotEmpty || _dst.isNotEmpty || _srcBuf.trim().isNotEmpty || _dstBuf.trim().isNotEmpty;

  void addSource(String delta, int? elapsedMs) {
    final ms = elapsedMs ?? _lastMs;
    _lastMs = ms;
    if (_srcBuf.trim().isEmpty) _srcBufStartMs = ms;
    _srcBuf += delta;
    final cut = cutSentences(_srcBuf);
    for (var i = 0; i < cut.sentences.length; i++) {
      _queueSource(cut.sentences[i], i == 0 ? (_srcBufStartMs ?? ms) : ms);
    }
    if (cut.sentences.isNotEmpty) {
      _srcBuf = cut.rest;
      _srcBufStartMs = cut.rest.trim().isEmpty ? null : ms;
    }
    _pair();
    _limitBacklog();
  }

  void addTranslation(String delta) {
    _dstBuf += delta;
    final cut = cutSentences(_dstBuf);
    if (cut.sentences.isNotEmpty) {
      _dst.addAll(cut.sentences);
      _dstBuf = cut.rest;
    }
    _pair();
  }

  /// Both streams have been quiet for a while: close everything pending.
  void settle() {
    final rest = _srcBuf.trim();
    if (rest.isNotEmpty) _queueSource(rest, _srcBufStartMs ?? _lastMs);
    _srcBuf = '';
    _srcBufStartMs = null;
    final dRest = _dstBuf.trim();
    if (dRest.isNotEmpty) _dst.add(dRest);
    _dstBuf = '';

    _pair();

    if (_src.isNotEmpty) {
      final target = _lastPairedThisRound;
      if (target != null) {
        // The model merged sentences: fold the extra source into the last
        // translated sentence of this stretch of speech.
        final s = committed[target];
        committed[target] = s.copyWith(
          source: _join([s.source, for (final p in _src) p.text]),
        );
      } else {
        // Nothing was translated: likely the target language after all.
        for (final p in _src) {
          _commit(Sentence(at: p.at, source: p.text, translation: '', lang: guessLang(p.text)));
        }
      }
      _src.clear();
    }

    if (_dst.isNotEmpty) {
      final i = _lastIndexWhere((s) => !_isTargetLanguage(s.source)) ?? _lastIndexWhere((_) => true);
      if (i != null) {
        final s = committed[i];
        committed[i] = s.copyWith(translation: _join([s.translation, ..._dst]));
      }
      _dst.clear();
    }
    _lastPairedThisRound = null;
  }

  void _queueSource(String text, int ms) {
    final at = offset + Duration(milliseconds: ms);
    if (_isTargetLanguage(text)) {
      _commit(Sentence(at: at, source: text, translation: '', lang: target));
      return;
    }
    _src.add(_Pending(text, at));
  }

  bool _isTargetLanguage(String text) => guessLang(text) == target;

  void _pair() {
    while (_src.isNotEmpty && _dst.isNotEmpty) {
      final s = _src.removeAt(0);
      final t = _dst.removeAt(0);
      _lastPairedThisRound =
          _commit(Sentence(at: s.at, source: s.text, translation: t, lang: guessLang(s.text)));
    }
  }

  void _limitBacklog() {
    if (_src.length < maxBacklog) return;
    // The translation is lagging far behind (or has no punctuation): show
    // the backlog as one block with whatever translation exists.
    final first = _src.first;
    final translation = _join([..._dst, _dstBuf.trim()]);
    _lastPairedThisRound = _commit(Sentence(
      at: first.at,
      source: _join([for (final p in _src) p.text]),
      translation: translation,
      lang: guessLang(first.text),
    ));
    _src.clear();
    _dst.clear();
    _dstBuf = '';
  }

  /// Adds a finished sentence from elsewhere (the user's reply) in time
  /// order.
  void insert(Sentence s) => _commit(s);

  /// Inserts in time order and returns the index used.
  int _commit(Sentence s) {
    var i = committed.length;
    while (i > 0 && committed[i - 1].at > s.at) {
      i--;
    }
    committed.insert(i, s);
    if (_lastPairedThisRound != null && _lastPairedThisRound! >= i) {
      _lastPairedThisRound = _lastPairedThisRound! + 1;
    }
    return i;
  }

  int? _lastIndexWhere(bool Function(Sentence) test) {
    for (var i = committed.length - 1; i >= 0; i--) {
      if (test(committed[i])) return i;
    }
    return null;
  }
}

class _Pending {
  _Pending(this.text, this.at);
  final String text;
  final Duration at;
}

bool _isCjk(String s) {
  if (s.isEmpty) return false;
  final r = s.runes.first;
  return r >= 0x3000 && r <= 0x9FFF;
}

bool _endsCjk(String s) {
  if (s.isEmpty) return false;
  final r = s.runes.last;
  return r >= 0x3000 && r <= 0x9FFF || r >= 0xFF00 && r <= 0xFFEF;
}

/// Joins pieces with a space, except between Chinese text.
String _join(Iterable<String> parts) {
  final b = StringBuffer();
  for (final raw in parts) {
    final p = raw.trim();
    if (p.isEmpty) continue;
    final prev = b.toString();
    if (prev.isNotEmpty && !(_endsCjk(prev) && _isCjk(p))) b.write(' ');
    b.write(p);
  }
  return b.toString();
}

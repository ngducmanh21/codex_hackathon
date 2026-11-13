import 'lang.dart';

/// One finished sentence: what was said and its translation.
///
/// [translation] is empty when the sentence was already in the target
/// language, in which case only the original line is shown.
class Sentence {
  const Sentence({
    required this.at,
    required this.source,
    required this.translation,
    this.lang,
    this.speaker,
    this.marked = false,
  });

  /// Offset from the start of the recording.
  final Duration at;

  /// Language that was spoken, when known.
  final Lang? lang;

  final String source;
  final String translation;

  /// 0 = the user ("Tôi trả lời"); null = heard in the room. 1 is kept
  /// for items saved by the former dialogue screen.
  final int? speaker;

  /// Bookmarked by the user (the flag beside each caption).
  final bool marked;

  bool get hasTranslation => translation.trim().isNotEmpty;

  Sentence copyWith({String? source, String? translation, Lang? lang, bool? marked}) =>
      Sentence(
        at: at,
        source: source ?? this.source,
        translation: translation ?? this.translation,
        lang: lang ?? this.lang,
        speaker: speaker,
        marked: marked ?? this.marked,
      );

  Map<String, Object?> toJson() => {
        'at': at.inMilliseconds,
        if (lang != null) 'lang': lang!.code,
        'source': source,
        'translation': translation,
        if (speaker != null) 'speaker': speaker,
        if (marked) 'marked': true,
      };

  factory Sentence.fromJson(Map<String, Object?> j) => Sentence(
        at: Duration(milliseconds: (j['at'] as num?)?.toInt() ?? 0),
        lang: Lang.fromCode(j['lang'] as String?),
        source: j['source'] as String? ?? '',
        translation: j['translation'] as String? ?? '',
        speaker: (j['speaker'] as num?)?.toInt(),
        marked: j['marked'] == true,
      );
}

/// A term the user wants translated a particular way.
class Term {
  const Term(this.source, this.target);
  final String source;
  final String target;

  Map<String, Object?> toJson() => {'source': source, 'target': target};
  factory Term.fromJson(Map<String, Object?> j) =>
      Term(j['source'] as String? ?? '', j['target'] as String? ?? '');

  @override
  bool operator ==(Object other) =>
      other is Term && other.source == source && other.target == target;
  @override
  int get hashCode => Object.hash(source, target);
}

/// "Thêm ngữ cảnh": the topic and terms of a recording.
class MeetingContext {
  const MeetingContext({this.topic = '', this.terms = const []});

  final String topic;
  final List<Term> terms;

  bool get isEmpty => topic.trim().isEmpty && terms.isEmpty;

  /// Adds [other]'s terms (keeping this context's rendering of a term both
  /// have) and takes its topic when this one has none.
  MeetingContext merge(MeetingContext other) {
    final known = {for (final t in terms) t.source.toLowerCase()};
    return MeetingContext(
      topic: topic.trim().isEmpty ? other.topic : topic,
      terms: [
        ...terms,
        for (final t in other.terms)
          if (known.add(t.source.toLowerCase())) t,
      ],
    );
  }

  MeetingContext copyWith({String? topic, List<Term>? terms}) =>
      MeetingContext(topic: topic ?? this.topic, terms: terms ?? this.terms);

  Map<String, Object?> toJson() => {
        'topic': topic,
        'terms': [for (final t in terms) t.toJson()],
      };

  factory MeetingContext.fromJson(Map<String, Object?>? j) {
    if (j == null) return const MeetingContext();
    return MeetingContext(
      topic: j['topic'] as String? ?? '',
      terms: [
        for (final t in (j['terms'] as List? ?? const []))
          Term.fromJson((t as Map).cast<String, Object?>()),
      ],
    );
  }
}

/// A structured meeting summary.
class Summary {
  const Summary({
    required this.overview,
    this.decisions = const [],
    this.actions = const [],
    this.openQuestions = const [],
  });

  final String overview;
  final List<String> decisions;
  final List<ActionItem> actions;
  final List<String> openQuestions;

  Map<String, Object?> toJson() => {
        'overview': overview,
        'decisions': decisions,
        'actions': [for (final a in actions) a.toJson()],
        'open_questions': openQuestions,
      };

  factory Summary.fromJson(Map<String, Object?> j) => Summary(
        overview: j['overview'] as String? ?? '',
        decisions: _strings(j['decisions']),
        actions: [
          for (final a in (j['actions'] as List? ?? const []))
            ActionItem.fromJson((a as Map).cast<String, Object?>()),
        ],
        openQuestions: _strings(j['open_questions']),
      );
}

class ActionItem {
  const ActionItem({required this.task, this.owner = '', this.due = ''});
  final String task;
  final String owner;
  final String due;

  Map<String, Object?> toJson() => {'task': task, 'owner': owner, 'due': due};
  factory ActionItem.fromJson(Map<String, Object?> j) => ActionItem(
        task: j['task'] as String? ?? '',
        owner: j['owner'] as String? ?? '',
        due: j['due'] as String? ?? '',
      );
}

/// One question asked about a saved item and its answer.
class QaPair {
  const QaPair({required this.question, required this.answer, this.refs = const []});
  final String question;
  final String answer;

  /// Timestamps ("mm:ss") of the sentences the answer relies on.
  final List<String> refs;

  Map<String, Object?> toJson() =>
      {'question': question, 'answer': answer, 'refs': refs};
  factory QaPair.fromJson(Map<String, Object?> j) => QaPair(
        question: j['question'] as String? ?? '',
        answer: j['answer'] as String? ?? '',
        refs: _strings(j['refs']),
      );
}

/// [dialogue] stays so items saved by the former dialogue screen still open.
enum ItemKind { meeting, dialogue, upload }

/// A saved meeting, dialogue or uploaded file in the Library.
class LibraryItem {
  const LibraryItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    required this.duration,
    required this.targetLang,
    required this.sentences,
    this.sourceLang,
    this.context = const MeetingContext(),
    this.summary,
    this.qa = const [],
  });

  final String id;
  final ItemKind kind;
  final String title;
  final DateTime createdAt;
  final Duration duration;

  /// Spoken language chosen by the user; null means auto-detect.
  /// For a dialogue this is "my" language.
  final Lang? sourceLang;

  /// "Dịch sang". For a dialogue, the other person's language.
  final Lang targetLang;

  final MeetingContext context;
  final List<Sentence> sentences;
  final Summary? summary;
  final List<QaPair> qa;

  LibraryItem copyWith({
    String? title,
    Summary? summary,
    List<QaPair>? qa,
    List<Sentence>? sentences,
    MeetingContext? context,
  }) =>
      LibraryItem(
        id: id,
        kind: kind,
        title: title ?? this.title,
        createdAt: createdAt,
        duration: duration,
        sourceLang: sourceLang,
        targetLang: targetLang,
        context: context ?? this.context,
        sentences: sentences ?? this.sentences,
        summary: summary ?? this.summary,
        qa: qa ?? this.qa,
      );

  Map<String, Object?> toJson() => {
        'version': 1,
        'id': id,
        'kind': kind.name,
        'title': title,
        'created_at': createdAt.toUtc().toIso8601String(),
        'duration_ms': duration.inMilliseconds,
        if (sourceLang != null) 'source_lang': sourceLang!.code,
        'target_lang': targetLang.code,
        'context': context.toJson(),
        'sentences': [for (final s in sentences) s.toJson()],
        if (summary != null) 'summary': summary!.toJson(),
        'qa': [for (final q in qa) q.toJson()],
      };

  factory LibraryItem.fromJson(Map<String, Object?> j) => LibraryItem(
        id: j['id'] as String,
        kind: ItemKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => ItemKind.meeting,
        ),
        title: j['title'] as String? ?? '',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        duration: Duration(milliseconds: (j['duration_ms'] as num?)?.toInt() ?? 0),
        sourceLang: Lang.fromCode(j['source_lang'] as String?),
        targetLang: Lang.fromCode(j['target_lang'] as String?) ?? Lang.vi,
        context: MeetingContext.fromJson((j['context'] as Map?)?.cast<String, Object?>()),
        sentences: [
          for (final s in (j['sentences'] as List? ?? const []))
            Sentence.fromJson((s as Map).cast<String, Object?>()),
        ],
        summary: j['summary'] == null
            ? null
            : Summary.fromJson((j['summary'] as Map).cast<String, Object?>()),
        qa: [
          for (final q in (j['qa'] as List? ?? const []))
            QaPair.fromJson((q as Map).cast<String, Object?>()),
        ],
      );
}

/// "mm:ss" or "h:mm:ss".
String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

List<String> _strings(Object? v) =>
    [for (final e in (v as List? ?? const [])) e.toString()];

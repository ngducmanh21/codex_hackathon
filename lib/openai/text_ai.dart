import 'dart:convert';
import 'dart:typed_data';

import '../domain/lang.dart';
import '../domain/records.dart';
import 'openai_error.dart';
import 'responses_client.dart';

/// Text models, as listed on OpenAI's models page on 2026-11-13.
const fastTextModel = 'gpt-6-luna';
const qualityTextModel = 'gpt-6.1-terra';

typedef UsageSink = void Function(String model, int inputTokens, int outputTokens);

/// Translation, summary and Q&A over text, using the Responses API.
class TextAi {
  TextAi(this._client, {this.translationModel = fastTextModel, this.analysisModel = qualityTextModel, this.onUsage});

  final ResponsesClient _client;
  String translationModel;
  String analysisModel;
  UsageSink? onUsage;

  static const batchSize = 40;

  /// Translates [sentences] into [to], keeping order. Sentences already in
  /// [to] come back unchanged. Uses the context's glossary.
  Future<List<String>> translate(
    List<String> sentences, {
    required Lang to,
    MeetingContext context = const MeetingContext(),
  }) async {
    final out = <String>[];
    for (var i = 0; i < sentences.length; i += batchSize) {
      final batch = sentences.sublist(i, i + batchSize > sentences.length ? sentences.length : i + batchSize);
      final r = await _client.create(
        model: translationModel,
        instructions: translateInstructions(to, context),
        input: jsonEncode({'segments': batch}),
        schema: _translationsSchema,
        schemaName: 'translations',
      );
      _track(r);
      final list = _decodeObject(r.text)['translations'];
      if (list is! List || list.length != batch.length) {
        throw const OpenAiException('Bản dịch trả về không khớp số câu.', code: 'bad_shape');
      }
      out.addAll(list.map((e) => e.toString()));
    }
    return out;
  }

  /// Summary of a saved item, written in [readingLang].
  Future<Summary> summarize(LibraryItem item, {required Lang readingLang}) async {
    final r = await _client.create(
      model: analysisModel,
      instructions: summaryInstructions(readingLang, item.context),
      input: transcriptForPrompt(item),
      schema: _summarySchema,
      schemaName: 'meeting_summary',
    );
    _track(r);
    return Summary.fromJson(_decodeObject(r.text));
  }

  /// Answers [question] from the transcript, citing the lines it used.
  Future<QaPair> ask(LibraryItem item, String question) async {
    final r = await _client.create(
      model: analysisModel,
      instructions: qaInstructions(item.context),
      input: '${transcriptForPrompt(item)}\n\nQUESTION:\n$question',
      schema: _qaSchema,
      schemaName: 'answer',
    );
    _track(r);
    final j = _decodeObject(r.text);
    return QaPair(
      question: question,
      answer: j['answer'] as String? ?? '',
      refs: [for (final e in (j['refs'] as List? ?? const [])) e.toString()],
    );
  }

  /// What [sentence] really means, its tone, and replies the user could
  /// give, for someone reading in [readingLang]. [recent] gives the
  /// surrounding conversation.
  Future<Explanation> explain(
    Sentence sentence, {
    required Lang readingLang,
    List<Sentence> recent = const [],
    MeetingContext context = const MeetingContext(),
  }) async {
    final replyLang = sentence.lang != null && sentence.lang != readingLang ? sentence.lang! : null;
    final b = StringBuffer('CONVERSATION SO FAR\n');
    for (final s in recent) {
      b.write('- ${s.source}');
      if (s.hasTranslation) b.write(' || ${s.translation}');
      b.writeln();
    }
    b
      ..writeln()
      ..writeln('SENTENCE TO EXPLAIN')
      ..writeln(sentence.source);
    if (sentence.hasTranslation) b.writeln('Machine translation: ${sentence.translation}');
    final r = await _client.create(
      model: analysisModel,
      instructions: explainInstructions(readingLang, replyLang, context),
      input: b.toString(),
      schema: _explainSchema,
      schemaName: 'explanation',
    );
    _track(r);
    return Explanation.fromJson(_decodeObject(r.text));
  }

  /// Reads a photo of a quote, catalogue, business card or slide and returns
  /// its topic and the names and terms worth keeping, rendered in [target].
  Future<MeetingContext> contextFromImage(
    Uint8List bytes, {
    required String mimeType,
    required Lang target,
  }) async {
    final r = await _client.create(
      model: analysisModel,
      instructions: imageContextInstructions(target),
      input: [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'Extract the context from this image.'},
            {'type': 'input_image', 'image_url': 'data:$mimeType;base64,${base64Encode(bytes)}'},
          ],
        },
      ],
      schema: _imageContextSchema,
      schemaName: 'image_context',
    );
    _track(r);
    final j = _decodeObject(r.text);
    return MeetingContext(
      topic: (j['topic'] as String? ?? '').trim(),
      terms: [
        for (final t in (j['terms'] as List? ?? const []))
          if (t is Map && (t['source'] as String? ?? '').trim().isNotEmpty)
            Term((t['source'] as String).trim(), ((t['target'] as String?) ?? '').trim()),
      ],
    );
  }

  void _track(TextResult r) =>
      onUsage?.call(r.model.isEmpty ? translationModel : r.model, r.inputTokens, r.outputTokens);
}

String glossaryBlock(MeetingContext c) {
  if (c.isEmpty) return '';
  final b = StringBuffer('\nCONTEXT\n');
  if (c.topic.trim().isNotEmpty) b.writeln('Topic: ${c.topic.trim()}');
  if (c.terms.isNotEmpty) {
    b.writeln('Glossary (source term => required rendering):');
    for (final t in c.terms) {
      b.writeln('- ${t.source} => ${t.target}');
    }
  }
  return b.toString();
}

String translateInstructions(Lang to, MeetingContext c) =>
    'You are a professional interpreter. Translate each item of "segments" '
    'into ${to.englishName}. Keep meaning, names and numbers exact and keep a '
    'natural spoken register. Whenever a glossary term appears in a segment, '
    'render it exactly as the glossary says. If a segment is already in '
    '${to.englishName}, return it unchanged. Return one translation per '
    'segment, in the same order.${glossaryBlock(c)}';

String summaryInstructions(Lang lang, MeetingContext c) =>
    'You summarise a recorded meeting or conversation from its transcript. '
    'Each line is "[label] original || translation". Write everything in '
    '${lang.englishName}. "overview": 2-4 sentences. "decisions": what was '
    'agreed. "actions": tasks with owner and due date when stated (empty '
    'string when not). "open_questions": what remains unresolved. Use only '
    'what the transcript says; never invent numbers or names.${glossaryBlock(c)}';

String qaInstructions(MeetingContext c) =>
    'Answer the QUESTION using only the TRANSCRIPT. Each line is '
    '"[label] original || translation". Answer in the language of the '
    'question, briefly. Put the labels of the lines you relied on in '
    '"refs" (for example "12:21" or "#4"). If the transcript does not '
    'contain the answer, say so plainly and return no refs.${glossaryBlock(c)}';

String explainInstructions(Lang reading, Lang? replyLang, MeetingContext c) =>
    'You help someone follow a live conversation in a language they do not '
    'speak. Explain the SENTENCE TO EXPLAIN for a reader of ${reading.englishName}, '
    'writing everything except the replies in ${reading.englishName}. '
    '"meaning": what the speaker actually means, in one or two sentences, '
    'fixing the machine translation if it is wrong. "nuance": tone and intent '
    '(polite refusal, pressure on price, a hint, a joke...) and anything '
    'cultural worth knowing, in one or two sentences; empty if nothing '
    'notable. "replies": two or three short replies the reader could say '
    'next; "text" in ${replyLang?.englishName ?? 'the speaker\'s language'}, '
    '"translation" in ${reading.englishName}. Use only the conversation given.'
    '${glossaryBlock(c)}';

String imageContextInstructions(Lang target) =>
    'The image is something a person brings to a meeting: a quotation, '
    'catalogue, product label, business card, slide or document. Return '
    '"topic": one short sentence in ${target.englishName} saying what the '
    'meeting is likely about. "terms": up to 20 proper names, product names, '
    'model numbers, units and technical terms that a speech translator could '
    'get wrong; "source" exactly as written in the image, "target" its '
    'rendering in ${target.englishName} (the same text for names and codes '
    'that should not be translated). Return empty values if the image holds '
    'no readable text.';

/// The transcript as numbered lines for a prompt.
String transcriptForPrompt(LibraryItem item) {
  final hasTimes = item.kind != ItemKind.upload;
  final b = StringBuffer('TRANSCRIPT\n');
  for (var i = 0; i < item.sentences.length; i++) {
    final s = item.sentences[i];
    final label = hasTimes ? formatClock(s.at) : '#${i + 1}';
    final who = s.speaker == null ? '' : (s.speaker == 0 ? 'Me: ' : 'Them: ');
    b.write('[$label] $who${s.source}');
    if (s.hasTranslation) b.write(' || ${s.translation}');
    b.writeln();
  }
  return b.toString();
}

Map<String, Object?> _decodeObject(String text) {
  try {
    return (jsonDecode(text) as Map).cast<String, Object?>();
  } on Object {
    throw const OpenAiException('OpenAI trả về dữ liệu không đọc được.', code: 'bad_json');
  }
}

const _translationsSchema = {
  'type': 'object',
  'properties': {
    'translations': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
  'required': ['translations'],
  'additionalProperties': false,
};

const _summarySchema = {
  'type': 'object',
  'properties': {
    'overview': {'type': 'string'},
    'decisions': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'actions': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'task': {'type': 'string'},
          'owner': {'type': 'string'},
          'due': {'type': 'string'},
        },
        'required': ['task', 'owner', 'due'],
        'additionalProperties': false,
      },
    },
    'open_questions': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
  'required': ['overview', 'decisions', 'actions', 'open_questions'],
  'additionalProperties': false,
};

const _qaSchema = {
  'type': 'object',
  'properties': {
    'answer': {'type': 'string'},
    'refs': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
  'required': ['answer', 'refs'],
  'additionalProperties': false,
};

const _explainSchema = {
  'type': 'object',
  'properties': {
    'meaning': {'type': 'string'},
    'nuance': {'type': 'string'},
    'replies': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
          'translation': {'type': 'string'},
        },
        'required': ['text', 'translation'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['meaning', 'nuance', 'replies'],
  'additionalProperties': false,
};

const _imageContextSchema = {
  'type': 'object',
  'properties': {
    'topic': {'type': 'string'},
    'terms': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'source': {'type': 'string'},
          'target': {'type': 'string'},
        },
        'required': ['source', 'target'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['topic', 'terms'],
  'additionalProperties': false,
};

/// "Giải thích" for one sentence.
class Explanation {
  const Explanation({required this.meaning, this.nuance = '', this.replies = const []});
  final String meaning;
  final String nuance;
  final List<({String text, String translation})> replies;

  factory Explanation.fromJson(Map<String, Object?> j) => Explanation(
        meaning: j['meaning'] as String? ?? '',
        nuance: j['nuance'] as String? ?? '',
        replies: [
          for (final r in (j['replies'] as List? ?? const []))
            if (r is Map) (text: r['text'] as String? ?? '', translation: r['translation'] as String? ?? ''),
        ],
      );
}

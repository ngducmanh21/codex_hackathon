import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/lang.dart';
import '../domain/records.dart';
import 'openai_error.dart';
import 'responses_client.dart';

/// File transcription model (OpenAI, 2026-11-13).
const fileTranscribeModel = 'gpt-transcribe';

/// OpenAI's upload limit for one transcription request.
const maxUploadBytes = 25 * 1024 * 1024;

class FileTranscript {
  const FileTranscript(this.text, {this.languages = const [], this.seconds});
  final String text;
  final List<Lang> languages;

  /// Billed audio length, when OpenAI reports it.
  final double? seconds;
}

/// `POST /v1/audio/transcriptions` for an uploaded audio file.
class TranscribeClient {
  TranscribeClient({
    required this.key,
    http.Client? httpClient,
    Uri? baseUrl,
    this.timeout = const Duration(minutes: 5),
  })  : _http = httpClient ?? http.Client(),
        _url = baseUrl ?? Uri.parse('https://api.openai.com/v1/audio/transcriptions');

  final KeyProvider key;
  final http.Client _http;
  final Uri _url;
  final Duration timeout;

  Future<FileTranscript> transcribe({
    required Uint8List bytes,
    required String fileName,
    Lang? language,
    MeetingContext context = const MeetingContext(),
  }) async {
    if (bytes.length > maxUploadBytes) {
      throw const OpenAiException(
        'Tệp lớn hơn 25 MB, giới hạn của OpenAI. Hãy cắt nhỏ hoặc nén tệp (vd. m4a/mp3).',
        code: 'file_too_large',
      );
    }
    final apiKey = await key();
    final req = http.MultipartRequest('POST', _url)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = fileTranscribeModel
      ..fields['response_format'] = 'json'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    if (language != null) req.fields['language'] = language.code;
    final prompt = transcriptionPrompt(context);
    if (prompt.isNotEmpty) req.fields['prompt'] = prompt;

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw const OpenAiException('Nhận dạng tệp quá lâu. Thử tệp ngắn hơn.');
    } on http.ClientException catch (e) {
      throw OpenAiException('Không kết nối được tới OpenAI: ${e.message}');
    }
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) throw OpenAiException.fromHttp(res.statusCode, body);
    return parseTranscription(body);
  }
}

/// A short hint with the topic and the terms, which helps spelling of names.
String transcriptionPrompt(MeetingContext c) {
  final parts = <String>[
    if (c.topic.trim().isNotEmpty) c.topic.trim(),
    if (c.terms.isNotEmpty) c.terms.map((t) => t.source).join(', '),
  ];
  return parts.join('. ');
}

FileTranscript parseTranscription(String body) {
  final j = (jsonDecode(body) as Map).cast<String, Object?>();
  final langs = <Lang>[];
  for (final l in (j['languages'] as List? ?? const [])) {
    final code = l is Map ? l['code'] as String? : l?.toString();
    final lang = Lang.fromCode(code);
    if (lang != null && !langs.contains(lang)) langs.add(lang);
  }
  final single = Lang.fromCode(j['language'] as String?);
  if (single != null && !langs.contains(single)) langs.add(single);
  final usage = (j['usage'] as Map?)?.cast<String, Object?>();
  return FileTranscript(
    j['text'] as String? ?? '',
    languages: langs,
    seconds: (usage?['seconds'] as num?)?.toDouble() ?? (j['duration'] as num?)?.toDouble(),
  );
}

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'openai_error.dart';

/// Supplies the API key at call time, so a key changed in Settings takes
/// effect without rebuilding clients. Throws [MissingKeyException].
typedef KeyProvider = Future<String> Function();

/// Result of one Responses API call.
class TextResult {
  const TextResult(this.text, {this.inputTokens = 0, this.outputTokens = 0, this.model = ''});
  final String text;
  final int inputTokens;
  final int outputTokens;
  final String model;
}

/// Minimal client for `POST /v1/responses` (OpenAI Responses API).
class ResponsesClient {
  ResponsesClient({
    required this.key,
    http.Client? httpClient,
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 90),
  })  : _http = httpClient ?? http.Client(),
        _url = baseUrl ?? Uri.parse('https://api.openai.com/v1/responses');

  final KeyProvider key;
  final http.Client _http;
  final Uri _url;
  final Duration timeout;

  /// Sends one request. With [schema], asks for strict JSON matching it.
  ///
  /// [input] is plain text, or a list of input items (for example a user
  /// message holding `input_text` and `input_image` parts).
  Future<TextResult> create({
    required String model,
    required String instructions,
    required Object input,
    Map<String, Object?>? schema,
    String schemaName = 'result',
    String reasoningEffort = 'none',
  }) async {
    final apiKey = await key();
    final body = <String, Object?>{
      'model': model,
      'instructions': instructions,
      'input': input,
      'reasoning': {'effort': reasoningEffort},
      // Personal app: do not keep conversations on OpenAI's side.
      'store': false,
      if (schema != null)
        'text': {
          'format': {
            'type': 'json_schema',
            'name': schemaName,
            'schema': schema,
            'strict': true,
          },
        },
    };
    final http.Response res;
    try {
      res = await _http
          .post(
            _url,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const OpenAiException('OpenAI trả lời quá lâu. Thử lại.');
    } on http.ClientException catch (e) {
      throw OpenAiException('Không kết nối được tới OpenAI: ${e.message}');
    }
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) throw OpenAiException.fromHttp(res.statusCode, text);
    return parseResponse(text);
  }
}

/// Extracts the output text from a Responses API body.
///
/// Walks `output[]` for `message` items and joins their `output_text`
/// parts; the text is not guaranteed to be at `output[0]`.
TextResult parseResponse(String body) {
  final j = (jsonDecode(body) as Map).cast<String, Object?>();
  final err = j['error'];
  if (err is Map) {
    throw OpenAiException(
      err['message'] as String? ?? 'OpenAI trả lỗi.',
      code: err['code'] as String?,
    );
  }
  final parts = <String>[];
  String? refusal;
  for (final item in (j['output'] as List? ?? const [])) {
    if (item is! Map || item['type'] != 'message') continue;
    for (final c in (item['content'] as List? ?? const [])) {
      if (c is! Map) continue;
      if (c['type'] == 'output_text') parts.add(c['text'] as String? ?? '');
      if (c['type'] == 'refusal') refusal = c['refusal'] as String?;
    }
  }
  if (parts.isEmpty) {
    throw OpenAiException(refusal ?? 'OpenAI không trả về nội dung.', code: refusal == null ? 'empty' : 'refusal');
  }
  final usage = (j['usage'] as Map?)?.cast<String, Object?>() ?? const {};
  return TextResult(
    parts.join(),
    inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
    outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
    model: j['model'] as String? ?? '',
  );
}

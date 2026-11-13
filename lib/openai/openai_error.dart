import 'dart:convert';

/// An error reported by OpenAI or by the connection to it.
///
/// Never carries request headers, so the API key cannot leak through an
/// error message or a log line.
class OpenAiException implements Exception {
  const OpenAiException(this.message, {this.status, this.code});

  final String message;
  final int? status;
  final String? code;

  bool get isAuth => status == 401 || status == 403 || code == 'invalid_api_key';
  bool get isRateLimit => status == 429;

  /// Text for the user, in Vietnamese.
  String get userMessage {
    if (isAuth) return 'Khoá OpenAI không hợp lệ hoặc không có quyền. Kiểm tra lại trong Cài đặt.';
    if (isRateLimit) return 'OpenAI đang giới hạn tốc độ hoặc tài khoản hết hạn mức. Thử lại sau.';
    if (status != null && status! >= 500) return 'OpenAI đang lỗi ($status). Thử lại sau.';
    return message;
  }

  /// Builds an exception from an HTTP error body such as
  /// `{"error": {"message": "...", "type": "...", "code": "..."}}`.
  factory OpenAiException.fromHttp(int status, String body) {
    String message = 'OpenAI trả lỗi $status';
    String? code;
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) {
        final e = j['error'] as Map;
        message = (e['message'] as String?) ?? message;
        code = (e['code'] ?? e['type'])?.toString();
      }
    } on FormatException {
      // Not JSON; keep the generic message.
    }
    return OpenAiException(message, status: status, code: code);
  }

  @override
  String toString() => 'OpenAiException(${status ?? '-'}, ${code ?? '-'}): $message';
}

/// Thrown when no API key has been saved yet.
class MissingKeyException implements Exception {
  const MissingKeyException();
  @override
  String toString() => 'Chưa có khoá OpenAI. Thêm khoá trong Cài đặt.';
}

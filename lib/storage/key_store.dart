import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../openai/openai_error.dart';

/// Where the OpenAI API key lives. The key is never written to a file,
/// a log or the Library.
abstract class KeyStore {
  Future<String?> read();
  Future<void> write(String key);
  Future<void> delete();
}

/// Android Keystore–backed storage.
class SecureKeyStore implements KeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  static const _name = 'openai_api_key';
  final FlutterSecureStorage _s;

  @override
  Future<String?> read() => _s.read(key: _name);

  @override
  Future<void> write(String key) => _s.write(key: _name, value: key.trim());

  @override
  Future<void> delete() => _s.delete(key: _name);
}

/// In-memory store for tests.
class MemoryKeyStore implements KeyStore {
  MemoryKeyStore([this._key]);
  String? _key;
  @override
  Future<String?> read() async => _key;
  @override
  Future<void> write(String key) async => _key = key.trim();
  @override
  Future<void> delete() async => _key = null;
}

/// A key provider that fails clearly when no key is saved.
Future<String> Function() keyProviderFor(KeyStore store) => () async {
      final k = await store.read();
      if (k == null || k.trim().isEmpty) throw const MissingKeyException();
      return k.trim();
    };

/// "sk-…ab12": enough to recognise the key without revealing it.
String maskKey(String key) {
  final k = key.trim();
  if (k.length <= 8) return '••••';
  return '${k.substring(0, 3)}…${k.substring(k.length - 4)}';
}

/// Checks that [key] works and can use the live translation model.
Future<void> checkKey(String key, {http.Client? client, String model = 'gpt-realtime-translate'}) async {
  final c = client ?? http.Client();
  try {
    final res = await c.get(
      Uri.parse('https://api.openai.com/v1/models/$model'),
      headers: {'Authorization': 'Bearer ${key.trim()}'},
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) return;
    if (res.statusCode == 404) {
      throw OpenAiException('Khoá hợp lệ nhưng chưa dùng được $model.', status: 404);
    }
    throw OpenAiException.fromHttp(res.statusCode, res.body);
  } finally {
    if (client == null) c.close();
  }
}

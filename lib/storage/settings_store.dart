import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/lang.dart';
import '../openai/text_ai.dart';

enum Quality { fast, careful }

/// OpenAI list prices used for the on-device estimate (USD, 2026-11-13).
abstract final class Prices {
  static const translatePerMinute = 0.034;
  static const transcribePerMinute = 0.0045;

  /// Per 1M tokens: (input, output).
  static const text = {
    fastTextModel: (0.10, 0.50),
    qualityTextModel: (1.0, 5.0),
  };
}

/// Usage in one calendar month.
class MonthUsage {
  double translateSeconds = 0;
  double transcribeSeconds = 0;
  final Map<String, (int, int)> tokens = {};

  double get dollars {
    var d = translateSeconds / 60 * Prices.translatePerMinute +
        transcribeSeconds / 60 * Prices.transcribePerMinute;
    tokens.forEach((model, t) {
      final p = Prices.text[_family(model)] ?? Prices.text[qualityTextModel]!;
      d += t.$1 / 1e6 * p.$1 + t.$2 / 1e6 * p.$2;
    });
    return d;
  }

  Map<String, Object?> toJson() => {
        'translate_s': translateSeconds,
        'transcribe_s': transcribeSeconds,
        'tokens': {for (final e in tokens.entries) e.key: [e.value.$1, e.value.$2]},
      };

  static MonthUsage fromJson(Map<String, Object?> j) {
    final u = MonthUsage()
      ..translateSeconds = (j['translate_s'] as num?)?.toDouble() ?? 0
      ..transcribeSeconds = (j['transcribe_s'] as num?)?.toDouble() ?? 0;
    (j['tokens'] as Map? ?? const {}).forEach((k, v) {
      final l = v as List;
      u.tokens[k as String] = ((l[0] as num).toInt(), (l[1] as num).toInt());
    });
    return u;
  }
}

/// Model ids may come back dated ("gpt-6-luna-2026-…"); price by prefix.
String _family(String model) {
  for (final k in Prices.text.keys) {
    if (model.startsWith(k)) return k;
  }
  return model;
}

/// App preferences and usage, stored as JSON next to the Library.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this.file);

  final File file;

  Quality quality = Quality.fast;
  Lang meetingTarget = Lang.vi;
  bool meetingReadAloud = false;
  final Map<String, MonthUsage> _usage = {};

  String get translationModel => quality == Quality.fast ? fastTextModel : qualityTextModel;

  static String monthKey(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}';

  MonthUsage usageFor(DateTime t) => _usage.putIfAbsent(monthKey(t), MonthUsage.new);

  Future<void> load() async {
    if (!await file.exists()) return;
    try {
      final j = (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
      quality = j['quality'] == 'careful' ? Quality.careful : Quality.fast;
      meetingTarget = Lang.fromCode(j['meeting_target'] as String?) ?? Lang.vi;
      meetingReadAloud = j['meeting_read_aloud'] == true;
      (j['usage'] as Map? ?? const {}).forEach((k, v) {
        _usage[k as String] = MonthUsage.fromJson((v as Map).cast<String, Object?>());
      });
    } on Object {
      // Bad settings file: start from defaults rather than failing.
    }
  }

  Future<void> _chain = Future.value();

  /// Saves; calls are serialised so two writes never race on the file.
  Future<void> save() => _chain = _chain.then((_) => _write()).catchError((Object _) {});

  Future<void> _write() async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'quality': quality.name,
      'meeting_target': meetingTarget.code,
      'meeting_read_aloud': meetingReadAloud,
      'usage': {for (final e in _usage.entries) e.key: e.value.toJson()},
    }));
    await tmp.rename(file.path);
    notifyListeners();
  }

  void addTranslateAudio(Duration d) {
    usageFor(DateTime.now()).translateSeconds += d.inMilliseconds / 1000;
    save();
  }

  void addTranscribeSeconds(double s) {
    usageFor(DateTime.now()).transcribeSeconds += s;
    save();
  }

  void addTokens(String model, int input, int output) {
    final u = usageFor(DateTime.now());
    final t = u.tokens[model] ?? (0, 0);
    u.tokens[model] = (t.$1 + input, t.$2 + output);
    save();
  }
}

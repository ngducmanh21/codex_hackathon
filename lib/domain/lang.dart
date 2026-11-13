/// Languages the app speaks. The code is the ISO 639-1 code OpenAI accepts.
enum Lang {
  vi('vi', 'Tiếng Việt', 'tiếng Việt', 'Vietnamese', 'Việt'),
  zh('zh', '中文', 'tiếng Trung', 'Mandarin Chinese (Simplified)', 'Trung'),
  en('en', 'English', 'tiếng Anh', 'English', 'Anh');

  const Lang(this.code, this.label, this.viName, this.englishName, this.short);

  /// ISO 639-1 code sent to the API.
  final String code;

  /// Name written in the language itself, used on chips.
  final String label;

  /// Vietnamese name, used inside sentences ("Dịch sang tiếng Trung").
  final String viName;

  /// English name, used inside prompts.
  final String englishName;

  /// Short Vietnamese tag on each caption: "Việt", "Trung", "Anh".
  final String short;

  /// "Tiếng Việt", "Tiếng Trung", "Tiếng Anh".
  String get viTitle => 'Tiếng $short';

  static Lang? fromCode(String? code) {
    if (code == null) return null;
    final c = code.toLowerCase();
    for (final l in Lang.values) {
      if (c == l.code || c.startsWith('${l.code}-') || c.startsWith('${l.code}_')) {
        return l;
      }
    }
    // Names some endpoints return instead of codes.
    switch (c) {
      case 'vietnamese':
        return Lang.vi;
      case 'chinese':
      case 'mandarin':
      case 'cmn':
        return Lang.zh;
      case 'english':
        return Lang.en;
    }
    return null;
  }
}

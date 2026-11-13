import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/lang.dart';

/// One line of the sample meeting, in the three languages.
class DemoLine {
  const DemoLine(this.spoken, {required this.vi, required this.zh, required this.en});
  final Lang spoken;
  final String vi;
  final String zh;
  final String en;

  String inLang(Lang l) => switch (l) {
        Lang.vi => vi,
        Lang.zh => zh,
        Lang.en => en,
      };

  String get said => inLang(spoken);
}

/// A supplier meeting about electronic parts: Chinese and English with one
/// Vietnamese line, so captions, tags, filters and same-language lines can
/// all be tried.
const demoMeeting = <DemoLine>[
  DemoLine(Lang.zh, zh: '大家好，我们开始吧。', vi: 'Chào mọi người, chúng ta bắt đầu nhé.', en: "Hello everyone, let's get started."),
  DemoLine(Lang.zh,
      zh: '这次的样品大家都看过了吧？', vi: 'Mọi người đã xem mẫu lần này rồi chứ?', en: 'Has everyone seen the samples this time?'),
  DemoLine(Lang.vi,
      vi: 'Rồi, chất lượng ổn nhưng giá còn hơi cao.',
      zh: '看过了，质量不错，但是价格有点高。',
      en: 'Yes, the quality is fine but the price is a bit high.'),
  DemoLine(Lang.zh,
      zh: '如果订单超过五百件，我们可以把单价降到两块三五。',
      vi: 'Nếu đơn hàng trên 500 chiếc, chúng tôi có thể giảm đơn giá xuống 2,35.',
      en: 'If the order exceeds 500 units, we can lower the unit price to 2.35.'),
  DemoLine(Lang.en,
      en: 'And what about the lead time for the second batch?',
      vi: 'Còn thời gian giao lô thứ hai thì sao?',
      zh: '那第二批的交货期呢？'),
  DemoLine(Lang.zh,
      zh: '贴片的部分我们下周就能开始，大概需要两周。',
      vi: 'Phần dán SMT tuần sau chúng tôi có thể bắt đầu, mất khoảng hai tuần.',
      en: 'We can start the SMT work next week; it takes about two weeks.'),
  DemoLine(Lang.zh,
      zh: 'MOQ的话，我们最低要五百件。', vi: 'Về MOQ, tối thiểu chúng tôi cần 500 chiếc.', en: 'As for MOQ, our minimum is 500 units.'),
  DemoLine(Lang.zh,
      zh: '请在周五之前把最新的BOM发给我们。',
      vi: 'Vui lòng gửi BOM mới nhất cho chúng tôi trước thứ Sáu.',
      en: 'Please send us the latest BOM before Friday.'),
];

/// What "Phát biểu" says back in the demo.
const demoReply = DemoLine(Lang.vi,
    vi: 'Được, chúng tôi đồng ý giá 2,35 nếu giao trước ngày 20.',
    zh: '好的，如果20号之前交货，我们同意2.35的价格。',
    en: 'OK, we agree to 2.35 if delivered before the 20th.');

/// Finds a sample line written in any language.
DemoLine? demoLineFor(String text) {
  final t = text.trim();
  for (final l in [...demoMeeting, demoReply]) {
    if (l.vi == t || l.zh == t || l.en == t) return l;
  }
  return null;
}

/// Splits a line the way a streaming model sends it: a few characters of
/// Chinese, or a word with its trailing space.
List<String> demoChunks(String text) {
  final out = <String>[];
  if (RegExp(r'[一-鿿]').hasMatch(text)) {
    for (var i = 0; i < text.length; i += 3) {
      out.add(text.substring(i, math.min(i + 3, text.length)));
    }
    return out;
  }
  // Every word keeps its trailing space, the last one too, so the next
  // sentence does not stick to this one.
  for (final w in text.split(' ')) {
    out.add('$w ');
  }
  return out;
}

/// A soft sine tone, 16-bit mono PCM: the stand-in for synthesized speech.
Uint8List demoTone({
  required Duration length,
  double frequency = 660,
  double volume = 0.2,
  int sampleRate = 24000,
}) {
  final n = sampleRate * length.inMilliseconds ~/ 1000;
  final data = ByteData(n * 2);
  final fade = sampleRate ~/ 50; // 20 ms in and out, no clicks
  for (var i = 0; i < n; i++) {
    var amp = volume;
    if (i < fade) amp *= i / fade;
    if (n - i < fade) amp *= (n - i) / fade;
    final v = (math.sin(2 * math.pi * frequency * i / sampleRate) * amp * 32767).round();
    data.setInt16(i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

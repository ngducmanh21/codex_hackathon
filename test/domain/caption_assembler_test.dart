import 'package:flutter_test/flutter_test.dart';
import 'package:scoai_voice_openai/domain/caption_assembler.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/domain/segmenter.dart';

void main() {
  group('cutSentences', () {
    test('keeps decimals and waits for the space after a Latin full stop', () {
      final r = cutSentences('The price is 2.35 dollars. Next');
      expect(r.sentences, ['The price is 2.35 dollars.']);
      expect(r.rest, ' Next');
      expect(cutSentences('Done.').sentences, isEmpty, reason: 'more text may follow');
    });

    test('a full stop followed straight by a capital letter ends a sentence', () {
      final r = cutSentences('bắt đầu nhé.Mọi người. Ok');
      expect(r.sentences, ['bắt đầu nhé.', 'Mọi người.']);
      expect(cutSentences('Giá 2.35 USD').sentences, isEmpty);
    });

    test('CJK punctuation ends a sentence at once', () {
      final r = cutSentences('这次的样品看过了吧？我们可以降价。还有');
      expect(r.sentences, ['这次的样品看过了吧？', '我们可以降价。']);
      expect(r.rest, '还有');
    });

    test('guessLang tells the three languages apart by script', () {
      expect(guessLang('我们可以降价'), Lang.zh);
      expect(guessLang('Giá còn hơi cao'), Lang.vi);
      expect(guessLang('The price is fine'), Lang.en);
      expect(guessLang('123 ...'), isNull);
    });
  });

  group('CaptionAssembler', () {
    late CaptionAssembler a;
    setUp(() => a = CaptionAssembler(target: Lang.vi));

    void say(String s, int ms) => a.addSource(s, ms);
    void tr(String s) => a.addTranslation(s);

    test('pairs streamed source and translation sentences in order', () {
      say('这次的样品', 0);
      say('大家都看过了吧？', 600);
      expect(a.committed, isEmpty);
      expect(a.liveSource, '这次的样品大家都看过了吧？');
      tr('Mọi người đã xem');
      expect(a.liveTranslation, 'Mọi người đã xem');
      tr(' mẫu lần này rồi chứ? ');
      expect(a.committed, hasLength(1));
      expect(a.committed.single.source, '这次的样品大家都看过了吧？');
      expect(a.committed.single.translation, 'Mọi người đã xem mẫu lần này rồi chứ?');
      expect(a.committed.single.lang, Lang.zh);
      expect(a.committed.single.at, Duration.zero);
      expect(a.hasPending, isFalse);
    });

    test('a sentence already in the target language stands alone, in time order', () {
      say('如果订单超过五百件，', 0);
      say('我们可以降价。', 1000);
      say('Rồi, giá còn hơi cao. ', 3000);
      // The Vietnamese line needs no translation and is committed at once,
      // while the Chinese one still waits for its translation.
      expect(a.committed.single.source, 'Rồi, giá còn hơi cao.');
      expect(a.committed.single.hasTranslation, isFalse);
      tr('Nếu đơn hàng trên 500 chiếc, chúng tôi có thể giảm giá. ');
      expect(a.committed.map((s) => s.lang), [Lang.zh, Lang.vi], reason: 'sorted by time');
      expect(a.committed.first.translation, startsWith('Nếu đơn hàng'));
    });

    test('settle folds an unpaired source sentence into the last translated one', () {
      say('样品看过了。', 0);
      say('质量不错。', 900);
      // The model merged both sentences into one translation.
      tr('Đã xem mẫu, chất lượng tốt. ');
      expect(a.committed, hasLength(1));
      a.settle();
      expect(a.committed, hasLength(1));
      expect(a.committed.single.source, '样品看过了。质量不错。');
      expect(a.committed.single.translation, 'Đã xem mẫu, chất lượng tốt.');
    });

    test('settle without any translation keeps the source on its own', () {
      say('嗯', 0);
      a.settle();
      expect(a.committed.single.source, '嗯');
      expect(a.committed.single.translation, '');
    });

    test('a translation that arrives after the pause joins the last sentence', () {
      say('交货期大概需要两周', 0);
      a.settle();
      expect(a.committed.single.translation, '');
      tr('Thời gian giao hàng khoảng hai tuần');
      a.settle();
      expect(a.committed, hasLength(1));
      expect(a.committed.single.translation, 'Thời gian giao hàng khoảng hai tuần');
    });

    test('a long backlog without translation is shown as one block', () {
      final b = CaptionAssembler(target: Lang.vi, maxBacklog: 3);
      b.addSource('第一句。第二句。', 0);
      b.addTranslation('Câu một');
      b.addSource('第三句。', 2000);
      expect(b.committed, hasLength(1));
      expect(b.committed.single.source, '第一句。第二句。第三句。');
      expect(b.committed.single.translation, 'Câu một');
      expect(b.hasPending, isFalse);
    });

    test('times are offset by the session start', () {
      a.offset = const Duration(minutes: 50);
      say('第二个会话。', 1500);
      tr('Phiên thứ hai. ');
      expect(a.committed.single.at, const Duration(minutes: 50, milliseconds: 1500));
    });

    test('English source joins with spaces, Chinese without', () {
      final en = CaptionAssembler(target: Lang.vi);
      en.addSource('We agree. ', 0);
      en.addSource('Ship it. ', 500);
      en.addTranslation('Chúng tôi đồng ý, giao hàng đi. ');
      en.settle();
      expect(en.committed.single.source, 'We agree. Ship it.');
    });
  });
}

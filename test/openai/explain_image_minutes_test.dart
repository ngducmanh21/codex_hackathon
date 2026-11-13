import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scoai_voice_openai/domain/lang.dart';
import 'package:scoai_voice_openai/domain/records.dart';
import 'package:scoai_voice_openai/openai/responses_client.dart';
import 'package:scoai_voice_openai/openai/text_ai.dart';
import 'package:scoai_voice_openai/share/minutes.dart';

String reply(Object json) => jsonEncode({
      'output': [
        {
          'type': 'message',
          'content': [
            {'type': 'output_text', 'text': jsonEncode(json)},
          ],
        },
      ],
    });

void main() {
  late List<Map<String, Object?>> requests;
  late String answer;
  TextAi ai() => TextAi(ResponsesClient(
        key: () async => 'sk-x',
        httpClient: MockClient((req) async {
          requests.add((jsonDecode(req.body) as Map).cast<String, Object?>());
          return http.Response.bytes(utf8.encode(answer), 200);
        }),
      ));
  setUp(() => requests = []);

  test('Giải thích: meaning, tone and replies in the speaker language', () async {
    answer = reply({
      'meaning': 'Họ muốn bạn đặt nhiều hơn mới giảm giá.',
      'nuance': 'Lời từ chối lịch sự.',
      'replies': [
        {'text': '如果我们订一千件呢？', 'translation': 'Nếu chúng tôi đặt 1000 chiếc thì sao?'},
      ],
    });
    const s = Sentence(at: Duration.zero, source: '这个价格我们很难再降了。', translation: 'Giá này khó giảm thêm.', lang: Lang.zh);
    final x = await ai().explain(
      s,
      readingLang: Lang.vi,
      recent: const [Sentence(at: Duration.zero, source: '能便宜一点吗？', translation: 'Rẻ hơn được không?', lang: Lang.zh)],
      context: const MeetingContext(terms: [Term('MOQ', 'số lượng tối thiểu')]),
    );
    expect(x.meaning, startsWith('Họ muốn'));
    expect(x.replies.single.text, '如果我们订一千件呢？');
    final r = requests.single;
    expect(r['model'], qualityTextModel);
    expect(r['instructions'], contains('reader of Vietnamese'));
    expect(r['instructions'], contains('"text" in Mandarin Chinese'));
    expect(r['instructions'], contains('MOQ => số lượng tối thiểu'));
    expect(r['input'], contains('- 能便宜一点吗？ || Rẻ hơn được không?'));
    expect(r['input'], contains('SENTENCE TO EXPLAIN\n这个价格我们很难再降了。'));
  });

  test('context from a photo sends the image inline and returns its terms', () async {
    answer = reply({
      'topic': 'Báo giá linh kiện SMT.',
      'terms': [
        {'source': 'MOQ', 'target': 'số lượng tối thiểu'},
        {'source': 'STM32F103', 'target': 'STM32F103'},
        {'source': '  ', 'target': 'bỏ'},
      ],
    });
    final found = await ai().contextFromImage(Uint8List.fromList([1, 2, 3]), mimeType: 'image/jpeg', target: Lang.vi);
    expect(found.topic, 'Báo giá linh kiện SMT.');
    expect(found.terms.map((t) => t.source), ['MOQ', 'STM32F103']);
    final content = ((requests.single['input'] as List).single as Map)['content'] as List;
    expect(content[1], {'type': 'input_image', 'image_url': 'data:image/jpeg;base64,AQID'});
    expect(requests.single['instructions'], contains('in Vietnamese'));

    // Terms already in the context keep their rendering.
    const mine = MeetingContext(topic: 'Đàm phán', terms: [Term('moq', 'MOQ')]);
    final merged = mine.merge(found);
    expect(merged.topic, 'Đàm phán');
    expect(merged.terms.map((t) => t.target), ['MOQ', 'STM32F103']);
  });

  group('minutesText', () {
    final item = LibraryItem(
      id: 'm1',
      kind: ItemKind.meeting,
      title: 'Họp nhà cung cấp',
      createdAt: DateTime(2026, 11, 12, 14, 30),
      duration: const Duration(minutes: 42),
      targetLang: Lang.vi,
      sentences: const [
        Sentence(at: Duration(minutes: 12, seconds: 21), source: '单价两块三五。', translation: 'Đơn giá 2,35.', lang: Lang.zh),
        Sentence(at: Duration(minutes: 13), source: 'Đồng ý.', translation: '同意。', lang: Lang.vi, speaker: 0),
      ],
      summary: const Summary(
        overview: 'Hai bên chốt giá.',
        decisions: ['Đơn giá 2,35 USD'],
        actions: [ActionItem(task: 'Gửi BOM', owner: 'Bên mình', due: 'thứ Sáu'), ActionItem(task: 'Xác nhận ngày giao')],
      ),
    );

    test('the minutes are the summary, ready to paste', () {
      final text = minutesText(item);
      expect(text, startsWith('Họp nhà cung cấp\n12/11/2026 14:30 · 42:00 · Dịch sang tiếng Việt'));
      expect(text, contains('TÓM TẮT\nHai bên chốt giá.'));
      expect(text, contains('ĐÃ CHỐT\n- Đơn giá 2,35 USD'));
      expect(text, contains('- Gửi BOM (Bên mình · thứ Sáu)\n- Xác nhận ngày giao\n'));
      expect(text, isNot(contains('CÒN BỎ NGỎ')));
      expect(text, isNot(contains('BẢN GHI')));
    });

    test('with the transcript: each line, its translation, and who replied', () {
      final text = minutesText(item, withTranscript: true);
      expect(text, contains('[12:21] Trung: 单价两块三五。\n    → Đơn giá 2,35.'));
      expect(text, contains('[13:00] Bạn: Đồng ý.\n    → 同意。'));
    });

    test('without a summary the transcript is sent anyway', () {
      final bare = LibraryItem.fromJson(item.toJson()..remove('summary'));
      expect(minutesText(bare), contains('BẢN GHI'));
    });
  });
}

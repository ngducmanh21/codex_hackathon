import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../domain/lang.dart';
import '../domain/segmenter.dart';
import 'demo_script.dart';

/// An HTTP client that answers OpenAI's Responses and transcription
/// endpoints with sample data, so every screen can be tried without a key.
/// Requests and responses keep OpenAI's shapes, so the app's real request
/// building and parsing run.
http.Client demoHttpClient({Duration delay = const Duration(milliseconds: 700)}) => MockClient((req) async {
      await Future<void>.delayed(delay);
      if (req.url.path.endsWith('/audio/transcriptions')) {
        return _json({
          'text': [for (final l in demoMeeting) l.said].join(' '),
          'languages': [
            {'code': 'zh'},
            {'code': 'en'},
            {'code': 'vi'},
          ],
        });
      }
      final body = (jsonDecode(req.body) as Map).cast<String, Object?>();
      final name = ((body['text'] as Map?)?['format'] as Map?)?['name'] as String?;
      final instructions = body['instructions'] as String? ?? '';
      final input = body['input'];
      final inputText = input is String ? input : '';
      final Object result = switch (name) {
        'translations' => _translations(instructions, inputText),
        'meeting_summary' => _summary,
        'answer' => _answer(inputText),
        'explanation' => _explanation(inputText),
        'image_context' => _imageContext,
        _ => {'text': 'Câu trả lời mẫu.'},
      };
      return _json({
        'model': 'demo',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': jsonEncode(result)},
            ],
          },
        ],
        'usage': {'input_tokens': 0, 'output_tokens': 0},
      });
    });

http.Response _json(Object o) => http.Response.bytes(
      utf8.encode(jsonEncode(o)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Lang _targetOf(String instructions) {
  if (instructions.contains('into Mandarin') || instructions.contains('in Mandarin')) return Lang.zh;
  if (instructions.contains('into English') || instructions.contains('in English.')) return Lang.en;
  return Lang.vi;
}

Map<String, Object?> _translations(String instructions, String input) {
  final target = _targetOf(instructions);
  final segments = ((jsonDecode(input) as Map)['segments'] as List).cast<String>();
  return {
    'translations': [
      for (final s in segments) demoLineFor(s)?.inLang(target) ?? (guessLang(s) == target ? s : '(bản dịch mẫu) $s'),
    ],
  };
}

const _summary = {
  'overview':
      'Hai bên xem mẫu linh kiện. Bên mình thấy chất lượng ổn nhưng giá cao; nhà cung cấp đề nghị 2,35 USD/chiếc cho đơn từ 500 chiếc và có thể dán SMT từ tuần sau, mất khoảng hai tuần.',
  'decisions': ['Đơn giá 2,35 USD/chiếc khi đặt từ 500 chiếc.', 'Số lượng đặt tối thiểu (MOQ) là 500 chiếc.'],
  'actions': [
    {'task': 'Gửi BOM mới nhất cho nhà cung cấp', 'owner': 'Bên mình', 'due': 'trước thứ Sáu'},
    {'task': 'Bắt đầu dán SMT', 'owner': 'Nhà cung cấp', 'due': 'tuần sau'},
  ],
  'open_questions': ['Thời gian giao lô thứ hai chưa chốt ngày cụ thể.'],
};

/// Label of the first transcript line holding any of [keys].
String? _refFor(String transcript, List<String> keys) {
  for (final line in transcript.split('\n')) {
    final m = RegExp(r'^\[([^\]]+)\]').firstMatch(line);
    if (m != null && keys.any(line.contains)) return m.group(1);
  }
  return null;
}

Map<String, Object?> _answer(String input) {
  final q = input.contains('QUESTION:') ? input.substring(input.lastIndexOf('QUESTION:')).toLowerCase() : '';
  String answer;
  String? ref;
  if (q.contains('giá') || q.contains('price') || q.contains('价')) {
    answer = 'Nhà cung cấp đề nghị 2,35 USD/chiếc nếu đơn hàng trên 500 chiếc.';
    ref = _refFor(input, ['两块三五', '2.35', '2,35']);
  } else if (q.contains('chốt') || q.contains('decid')) {
    answer = 'Đã chốt: đơn giá 2,35 USD/chiếc từ 500 chiếc, MOQ 500 chiếc. Ngày giao lô hai chưa chốt.';
    ref = _refFor(input, ['MOQ', '五百件']);
  } else if (q.contains('trả lời') || q.contains('chờ')) {
    answer = 'Họ đang chờ bên mình gửi BOM mới nhất trước thứ Sáu.';
    ref = _refFor(input, ['BOM']);
  } else {
    answer = 'Đây là câu trả lời mẫu của Chế độ thử. Khi dùng khoá OpenAI thật, câu trả lời sẽ dựa trên bản ghi của bạn.';
    ref = _refFor(input, ['']);
  }
  return {
    'answer': answer,
    'refs': [?ref],
  };
}

Map<String, Object?> _explanation(String input) {
  final marker = input.indexOf('SENTENCE TO EXPLAIN');
  final sentence = marker < 0 ? '' : input.substring(marker).split('\n').skip(1).firstWhere((_) => true, orElse: () => '');
  final lang = guessLang(sentence) ?? Lang.zh;
  final line = demoLineFor(sentence);
  final pricey = sentence.contains('价') || sentence.contains('price') || sentence.contains('降');
  return {
    'meaning': line != null ? 'Ý họ là: ${line.vi}' : 'Đây là phần giải thích mẫu của Chế độ thử cho câu bạn vừa chạm.',
    'nuance': pricey
        ? 'Họ đang ra điều kiện: muốn giá tốt thì phải đặt nhiều hơn. Có thể còn thương lượng được.'
        : 'Giọng lịch sự, mang tính thông báo; không có ý ép.',
    'replies': lang == Lang.zh
        ? [
            {'text': '如果我们订一千件，价格能再低一点吗？', 'translation': 'Nếu chúng tôi đặt 1000 chiếc, giá có thể thấp hơn nữa không?'},
            {'text': '我们需要和老板确认一下。', 'translation': 'Chúng tôi cần xác nhận lại với sếp.'},
          ]
        : [
            {'text': 'Could you do a better price for 1,000 units?', 'translation': 'Với 1000 chiếc thì giá tốt hơn được không?'},
            {'text': 'Let me check with my manager.', 'translation': 'Để tôi hỏi lại quản lý.'},
          ],
  };
}

const _imageContext = {
  'topic': 'Báo giá linh kiện điện tử từ nhà cung cấp ở Thâm Quyến (ảnh mẫu).',
  'terms': [
    {'source': 'MOQ', 'target': 'số lượng đặt tối thiểu'},
    {'source': '贴片', 'target': 'dán linh kiện SMT'},
    {'source': 'BOM', 'target': 'danh mục vật tư'},
    {'source': 'FOB Shenzhen', 'target': 'FOB Thâm Quyến'},
    {'source': 'STM32F103', 'target': 'STM32F103'},
  ],
};

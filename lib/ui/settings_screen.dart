import 'package:flutter/material.dart';

import '../app/services.dart';
import '../live/meeting_controller.dart' show describeError;
import '../storage/key_store.dart';
import '../storage/settings_store.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _key = TextEditingController();
  String? _saved;
  bool _editing = false;
  bool _checking = false;
  String? _keyError;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    Services.of(context).keys.read().then((k) {
      if (!mounted) return;
      setState(() {
        _saved = (k ?? '').trim().isEmpty ? null : k;
        _editing = _saved == null;
      });
    });
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final k = _key.text.trim();
    if (k.isEmpty) return;
    setState(() {
      _checking = true;
      _keyError = null;
    });
    final keys = Services.of(context).keys;
    try {
      await checkKey(k);
      await keys.write(k);
      if (!mounted) return;
      _key.clear();
      setState(() {
        _saved = k;
        _editing = false;
      });
      Services.of(context).libraryChanged();
      showSnack(context, 'Đã lưu khoá.');
    } on Object catch (e) {
      if (mounted) setState(() => _keyError = describeError(e));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _deleteKey() async {
    await Services.of(context).keys.delete();
    if (!mounted) return;
    setState(() {
      _saved = null;
      _editing = true;
    });
    Services.of(context).libraryChanged();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Services.of(context).settings;
    final usage = settings.usageFor(DateTime.now());
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const SectionLabel('Khoá OpenAI API'),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_saved != null && !_editing) ...[
                    Row(
                      children: [
                        const Icon(Icons.verified_user_outlined, color: C.success, size: 20),
                        const SizedBox(width: 10),
                        Text(maskKey(_saved!), style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Lưu trong bộ nhớ an toàn của máy. Chỉ gửi tới OpenAI.', style: text.bodySmall),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinePill(label: 'Thay khoá', height: 40, onPressed: () => setState(() => _editing = true)),
                        const SizedBox(width: 8),
                        OutlinePill(label: 'Xoá', height: 40, color: C.danger, onPressed: _deleteKey),
                      ],
                    ),
                  ] else ...[
                    TextField(
                      controller: _key,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(hintText: 'Dán khoá sk-…'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tạo khoá tại platform.openai.com › API keys. Khoá chỉ nằm trên máy này, trong bộ nhớ an toàn.',
                      style: text.bodySmall,
                    ),
                    if (_keyError != null) ...[
                      const SizedBox(height: 8),
                      Text(_keyError!, style: const TextStyle(color: C.danger, fontSize: 14)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: C.brand,
                            shape: const StadiumBorder(),
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: _checking ? null : _saveKey,
                          child: Text(_checking ? 'Đang kiểm tra…' : 'Lưu và kiểm tra'),
                        ),
                        if (_saved != null) ...[
                          const SizedBox(width: 8),
                          TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Huỷ')),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 26),
            const SectionLabel('Chế độ thử'),
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dùng dữ liệu mẫu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        SizedBox(height: 2),
                        Text(
                          'Thử mọi màn hình mà không cần khoá OpenAI, không tốn tiền. Micro và loa vẫn chạy thật; '
                          'câu nói, bản dịch, tóm tắt và hỏi đáp là kịch bản mẫu. Thư viện có thêm hai mục [Mẫu].',
                          style: TextStyle(fontSize: 13, color: C.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    key: const Key('demo-switch'),
                    value: settings.demoMode,
                    onChanged: (v) => Services.of(context).setDemoMode(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const SectionLabel('Chất lượng dịch tệp và thuật ngữ'),
            Row(
              children: [
                Expanded(
                  child: _QualityCard(
                    title: 'Nhanh',
                    subtitle: 'Rẻ nhất, đủ dùng',
                    selected: settings.quality == Quality.fast,
                    onTap: () {
                      settings.quality = Quality.fast;
                      settings.save();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QualityCard(
                    title: 'Kỹ hơn',
                    subtitle: 'Thuật ngữ tốt hơn',
                    selected: settings.quality == Quality.careful,
                    onTap: () {
                      settings.quality = Quality.careful;
                      settings.save();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Bản dịch trực tiếp khi họp luôn dùng mô hình dịch realtime của OpenAI.', style: text.bodySmall),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: C.sunken, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Chi phí tháng này', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        '≈ ${usage.dollars.toStringAsFixed(2)} USD',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Dịch trực tiếp ${(usage.translateSeconds / 60).toStringAsFixed(0)} phút · '
                    'tệp ${(usage.transcribeSeconds / 60).toStringAsFixed(0)} phút. '
                    'Ước tính trên máy theo bảng giá OpenAI ngày 13/11/2026; hoá đơn thật xem ở platform.openai.com.',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({required this.title, required this.subtitle, required this.selected, required this.onTap});
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: C.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: selected ? C.brand : C.hairline, width: selected ? 2 : 1),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: C.inkMuted)),
          ],
        ),
      ),
    ),
  );
}

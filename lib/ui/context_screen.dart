import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app/services.dart';
import '../domain/lang.dart';
import '../domain/records.dart';
import '../live/meeting_controller.dart' show describeError;
import 'theme.dart';
import 'widgets.dart';

/// "Thêm ngữ cảnh": topic plus terms. Returns the edited context on save.
class ContextScreen extends StatefulWidget {
  const ContextScreen({super.key, required this.initial, this.liveNote = false, this.target = Lang.vi});
  final MeetingContext initial;

  /// The language terms are rendered in ("Dịch sang").
  final Lang target;

  /// Explain that live translation cannot take a glossary.
  final bool liveNote;

  @override
  State<ContextScreen> createState() => _ContextScreenState();
}

class _ContextScreenState extends State<ContextScreen> {
  late final _topic = TextEditingController(text: widget.initial.topic);
  final _src = TextEditingController();
  final _dst = TextEditingController();
  late final List<Term> _terms = List.of(widget.initial.terms);
  bool _reading = false;

  @override
  void dispose() {
    _topic.dispose();
    _src.dispose();
    _dst.dispose();
    super.dispose();
  }

  void _add() {
    final s = _src.text.trim();
    if (s.isEmpty) return;
    final d = _dst.text.trim();
    setState(() {
      _terms.removeWhere((t) => t.source == s);
      _terms.add(Term(s, d.isEmpty ? s : d));
      _src.clear();
      _dst.clear();
    });
  }

  /// Reads a photo (quote, catalogue, business card, slide) and adds the
  /// topic and terms it finds.
  Future<void> _fromImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    if (picked == null || !mounted) return;
    final ai = Services.of(context).textAi;
    setState(() => _reading = true);
    try {
      final bytes = await picked.readAsBytes();
      final mime = picked.mimeType ?? (picked.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      final found = await ai.contextFromImage(bytes, mimeType: mime, target: widget.target);
      if (!mounted) return;
      final before = _terms.length;
      final merged = MeetingContext(topic: _topic.text, terms: _terms).merge(found);
      setState(() {
        if (_topic.text.trim().isEmpty) _topic.text = merged.topic;
        _terms
          ..clear()
          ..addAll(merged.terms);
      });
      final added = _terms.length - before;
      showSnack(context, added == 0 ? 'Không thấy thuật ngữ mới trong ảnh.' : 'Đã thêm $added thuật ngữ từ ảnh.');
    } on Object catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _save() {
    if (_src.text.trim().isNotEmpty) _add();
    Navigator.of(context).pop(MeetingContext(topic: _topic.text.trim(), terms: _terms));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      title: const Text('Ngữ cảnh'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        Text(
          widget.liveNote
              ? 'Giúp đúng tên riêng và thuật ngữ. Khi họp trực tiếp, câu có thuật ngữ được sửa lại sau khi nói xong; ngữ cảnh cũng dùng cho tóm tắt và hỏi đáp.'
              : 'Giúp nhận dạng và dịch đúng chủ đề, tên riêng và thuật ngữ.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 14, height: 20 / 14),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: _reading
              ? const Row(
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Expanded(child: Text('Đang đọc ảnh…')),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Lấy từ ảnh', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    const Text(
                      'Báo giá, catalog, danh thiếp, slide: AI tự điền tên riêng và thuật ngữ.',
                      style: TextStyle(fontSize: 13, color: C.inkMuted),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinePill(
                          key: const Key('context-camera'),
                          label: 'Chụp ảnh',
                          icon: Icons.photo_camera_outlined,
                          height: 40,
                          onPressed: () => _fromImage(ImageSource.camera),
                        ),
                        const SizedBox(width: 8),
                        OutlinePill(
                          key: const Key('context-gallery'),
                          label: 'Chọn ảnh',
                          icon: Icons.photo_library_outlined,
                          height: 40,
                          onPressed: () => _fromImage(ImageSource.gallery),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 22),
        const SectionLabel('Chủ đề'),
        TextField(
          controller: _topic,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Ví dụ: đàm phán đơn hàng linh kiện, giá FOB'),
        ),
        const SizedBox(height: 22),
        const SectionLabel('Thuật ngữ và tên riêng'),
        if (_terms.isNotEmpty)
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _terms.length; i++)
                  Container(
                    decoration: BoxDecoration(
                      border: i == _terms.length - 1 ? null : const Border(bottom: BorderSide(color: C.hairline)),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: _terms[i].source,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const TextSpan(
                                  text: '  →  ',
                                  style: TextStyle(color: C.inkMuted),
                                ),
                                TextSpan(text: _terms[i].target),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Xoá ${_terms[i].source}',
                          icon: const Icon(Icons.close, size: 18, color: C.inkMuted),
                          onPressed: () => setState(() => _terms.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _src,
                decoration: const InputDecoration(hintText: 'Từ gốc'),
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _dst,
                decoration: const InputDecoration(hintText: 'Dịch là'),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Thêm thuật ngữ',
              style: IconButton.styleFrom(backgroundColor: C.brand, fixedSize: const Size(48, 48)),
              onPressed: _add,
              icon: const Icon(Icons.add, color: Colors.white),
            ),
          ],
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.brand, shape: const StadiumBorder()),
            onPressed: _save,
            child: const Text('Lưu ngữ cảnh', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    ),
  );
}

/// The small card that shows a context and opens the editor.
class ContextCard extends StatelessWidget {
  const ContextCard({
    super.key,
    required this.value,
    required this.onChanged,
    this.liveNote = false,
    this.target = Lang.vi,
  });
  final MeetingContext value;
  final ValueChanged<MeetingContext> onChanged;
  final bool liveNote;
  final Lang target;

  Future<void> _edit(BuildContext context) async {
    final r = await Navigator.of(context).push<MeetingContext>(
      MaterialPageRoute(
        builder: (_) => ContextScreen(initial: value, liveNote: liveNote, target: target),
      ),
    );
    if (r != null) onChanged(r);
  }

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinePill(
          label: 'Thêm ngữ cảnh',
          icon: Icons.add,
          height: 40,
          color: C.ink,
          onPressed: () => _edit(context),
        ),
      );
    }
    final shown = value.terms.take(2).toList();
    return SurfaceCard(
      onTap: () => _edit(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Ngữ cảnh', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              const Text(
                'Sửa',
                style: TextStyle(fontWeight: FontWeight.w600, color: C.brand),
              ),
            ],
          ),
          if (value.topic.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              value.topic,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 14),
            ),
          ],
          if (value.terms.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in shown) _TermChip('${t.source} → ${t.target}'),
                if (value.terms.length > shown.length) _TermChip('+${value.terms.length - shown.length}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TermChip extends StatelessWidget {
  const _TermChip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: C.sunken, borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: const TextStyle(fontSize: 13)),
  );
}

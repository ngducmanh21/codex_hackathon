import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/lang.dart';
import '../domain/records.dart';
import '../domain/segmenter.dart';
import '../live/meeting_controller.dart' show describeError;
import '../openai/transcribe_client.dart';
import '../storage/library_store.dart';
import 'context_screen.dart';
import 'saved_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  String? _name;
  Uint8List? _bytes;
  Lang? _spoken;
  Lang? _target;
  MeetingContext _context = const MeetingContext();
  bool _summarize = true;
  String? _step;
  String? _error;

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty) return;
    final f = files.first;
    final bytes = await f.xFile.readAsBytes();
    setState(() {
      _name = f.name;
      _bytes = bytes;
      _error = bytes.length > maxUploadBytes ? 'Tệp lớn hơn 25 MB, giới hạn của OpenAI. Hãy cắt nhỏ hoặc nén tệp.' : null;
    });
  }

  Future<void> _process() async {
    final s = Services.of(context);
    final bytes = _bytes!;
    final target = _target ?? s.settings.meetingTarget;
    s.textAi.translationModel = s.settings.translationModel;
    setState(() {
      _error = null;
      _step = 'Đang nhận dạng giọng nói…';
    });
    try {
      final tr = await s.transcriber.transcribe(bytes: bytes, fileName: _name!, language: _spoken, context: _context);
      if (tr.seconds != null) s.settings.addTranscribeSeconds(tr.seconds!);
      final parts = splitSentences(tr.text);
      if (parts.isEmpty) throw StateError('Không nghe được lời nói nào trong tệp.');
      if (!mounted) return;
      setState(() => _step = 'Đang dịch ${parts.length} câu…');
      final translated = await s.textAi.translate(parts, to: target, context: _context);
      final sentences = <Sentence>[
        for (var i = 0; i < parts.length; i++)
          () {
            final lang = guessLang(parts[i]) ?? _spoken;
            final same = lang == target || translated[i].trim() == parts[i].trim();
            return Sentence(at: Duration.zero, source: parts[i], translation: same ? '' : translated[i].trim(), lang: lang);
          }(),
      ];
      final now = DateTime.now();
      final item = LibraryItem(
        id: newItemId(now),
        kind: ItemKind.upload,
        title: _name!,
        createdAt: now,
        duration: Duration(milliseconds: ((tr.seconds ?? 0) * 1000).round()),
        sourceLang: _spoken ?? (tr.languages.length == 1 ? tr.languages.first : null),
        targetLang: target,
        context: _context,
        sentences: sentences,
      );
      await s.library.save(item);
      s.libraryChanged();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => SavedScreen(itemId: item.id, autoSummarize: _summarize),
      ));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _step = null;
        _error = e is StateError ? e.message : describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Services.of(context).settings;
    final target = _target ?? settings.meetingTarget;
    final working = _step != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Tải âm thanh lên')),
      body: AbsorbPointer(
        absorbing: working,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            SurfaceCard(
              onTap: _pick,
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: C.brandSoft, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.music_note_outlined, color: C.brand),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name ?? 'Chưa chọn tệp', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      _bytes == null ? 'm4a, mp3, wav, ogg, webm… tối đa 25 MB' : '${(_bytes!.length / 1024 / 1024).toStringAsFixed(1)} MB',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ]),
                ),
                Text(_name == null ? 'Chọn tệp' : 'Đổi tệp', style: const TextStyle(fontWeight: FontWeight.w600, color: C.brand)),
              ]),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Ngôn ngữ trong tệp'),
            PillChoices<Lang?>(
              values: const [null, ...Lang.values],
              selected: _spoken,
              label: (l) => l?.label ?? 'Tự nhận',
              onChanged: (l) => setState(() => _spoken = l),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Dịch sang'),
            LangChoices(selected: target, onChanged: (l) => setState(() => _target = l)),
            const SizedBox(height: 24),
            ContextCard(value: _context, target: target, onChanged: (c) => setState(() => _context = c)),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: Text('Tóm tắt sau khi xử lý', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              Switch(value: _summarize, onChanged: (v) => setState(() => _summarize = v)),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: C.danger)),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: working
              ? SizedBox(
                  height: 56,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(_step!, style: Theme.of(context).textTheme.bodyMedium),
                  ]),
                )
              : AccentButton(
                  label: 'Xử lý và lưu',
                  onPressed: _bytes == null || _bytes!.length > maxUploadBytes ? null : _process,
                ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/lang.dart';
import '../domain/records.dart';
import 'context_screen.dart';
import 'meeting_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class MeetingSetupScreen extends StatefulWidget {
  const MeetingSetupScreen({super.key, this.suggestedTitle});

  /// Pre-fills the name, when started from an upcoming calendar meeting.
  final String? suggestedTitle;
  @override
  State<MeetingSetupScreen> createState() => _MeetingSetupScreenState();
}

class _MeetingSetupScreenState extends State<MeetingSetupScreen> {
  late final _title = TextEditingController(text: widget.suggestedTitle ?? '');
  Lang? _target;
  bool? _readAloud;
  MeetingContext _context = const MeetingContext();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final s = Services.of(context);
    final target = _target ?? s.settings.meetingTarget;
    final readAloud = _readAloud ?? s.settings.meetingReadAloud;
    if (!await s.hasKey()) {
      if (!mounted) return;
      showSnack(context, 'Thêm khoá OpenAI trước khi bắt đầu.');
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
      return;
    }
    s.settings
      ..meetingTarget = target
      ..meetingReadAloud = readAloud;
    s.settings.save();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            MeetingScreen(title: _title.text, target: target, readAloud: readAloud, meetingContext: _context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Services.of(context).settings;
    final target = _target ?? settings.meetingTarget;
    final readAloud = _readAloud ?? settings.meetingReadAloud;
    final now = DateTime.now();
    final today = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Về trang chính',
          icon: const Icon(Icons.chevron_left_rounded, size: 30, color: C.brand),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Cuộc họp', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('meeting-title'),
                  controller: _title,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: C.brand),
                  decoration: const InputDecoration(
                    hintText: 'Cuộc họp mới',
                    hintStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: C.lineStrong),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$today · chưa ghi', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_none_rounded, size: 40, color: C.inkMuted),
                    SizedBox(height: 6),
                    Text('Chưa ghi âm', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text(
                      'Người nói dùng tiếng Việt, Trung hay Anh đều được; app tự nhận.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, height: 20 / 14, color: C.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Row(
                    label: 'Dịch sang',
                    child: PillChoices<Lang>(
                      values: Lang.values,
                      selected: target,
                      label: (l) => l == Lang.vi ? l.viTitle : l.short,
                      onChanged: (l) => setState(() => _target = l),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 88, top: 4, bottom: 10),
                    child: Text(
                      'Câu đã nói bằng ${target.viName} chỉ hiện nguyên văn.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  _Row(
                    label: 'Ngữ cảnh',
                    child: ContextCard(
                      value: _context,
                      liveNote: true,
                      target: target,
                      onChanged: (c) => setState(() => _context = c),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _Row(
                    label: 'Đọc to',
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Đọc bản dịch, nên dùng tai nghe',
                            style: TextStyle(fontSize: 14, color: C.inkMuted),
                          ),
                        ),
                        Switch(value: readAloud, onChanged: (v) => setState(() => _readAloud = v)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AccentButton(
                    key: const Key('begin-recording'),
                    label: 'Bắt đầu ghi âm',
                    icon: Icons.mic_none,
                    onPressed: _start,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A left label (80 dp) and its control, as on SCOAI's setup screen.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: 80,
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.inkMuted),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: child),
    ],
  );
}

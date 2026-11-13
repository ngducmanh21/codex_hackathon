import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/lang.dart';
import '../domain/records.dart';
import '../domain/segmenter.dart';
import '../live/meeting_controller.dart';
import 'captions.dart';
import 'saved_screen.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets.dart';

/// The live meeting, after SCOAI Voice's compact meeting screen: captions
/// fill the screen and follow the newest sentence; each is the original
/// small and grey above its translation; Cả hai | Gốc | Dịch and a language
/// filter on top; read-aloud is the speaker in the top bar; one orange
/// "Tạm dừng | Hoàn tất" capsule below.
class MeetingScreen extends StatefulWidget {
  const MeetingScreen({
    super.key,
    required this.title,
    required this.target,
    required this.readAloud,
    required this.meetingContext,
    this.controller,
  });

  final String title;
  final Lang target;
  final bool readAloud;
  final MeetingContext meetingContext;

  /// For tests; built from [Services] otherwise.
  final MeetingController? controller;

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  MeetingController? _c;
  final _scroll = ScrollController();
  bool _awayFromLatest = false;
  bool _leaving = false;
  bool _resuming = false;
  CaptionView _view = CaptionView.both;
  Lang? _spoken;

  MeetingController get c => _c!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final s = Services.of(context);
    s.textAi.translationModel = s.settings.translationModel;
    _c =
        widget.controller ??
        MeetingController(
          opener: s.opener,
          mic: s.newMic(),
          speaker: s.speaker,
          store: s.library,
          target: widget.target,
          title: widget.title,
          context: widget.meetingContext,
          readAloud: widget.readAloud,
          textAi: s.textAi,
          awake: s.awake,
          background: s.background,
          onAudioBilled: s.onAudioBilled,
        );
    c.addListener(_onChange);
    _scroll.addListener(_onScroll);
    if (c.state == LiveState.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final away = _scroll.position.pixels < _scroll.position.maxScrollExtent - 48;
    if (away != _awayFromLatest) setState(() => _awayFromLatest = away);
  }

  void _onChange() {
    if (!mounted) return;
    if (_resuming && c.state != LiveState.starting) _resuming = false;
    setState(() {});
    if (!_awayFromLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toLatest(animate: false));
    }
  }

  void _toLatest({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(end, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(end);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    if (widget.controller == null) {
      if (c.state != LiveState.finished) c.discard();
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pauseOrResume() async {
    if (c.state == LiveState.paused) {
      setState(() => _resuming = true);
      await c.resume();
    } else {
      await c.pause();
    }
  }

  Future<void> _finish() async {
    final item = await c.finish();
    if (!mounted) return;
    Services.of(context).libraryChanged();
    _leaving = true;
    if (item == null) {
      showSnack(context, 'Chưa nghe được câu nào nên không lưu.');
      Navigator.of(context).pop();
      return;
    }
    await Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => SavedScreen(itemId: item.id, autoSummarize: true)));
  }

  Future<void> _confirmLeave() async {
    if (c.sentences.isEmpty && c.liveSource.isEmpty) {
      await c.discard();
      _leaving = true;
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kết thúc cuộc họp?'),
        content: const Text('Lưu vào Thư viện để xem lại, tóm tắt và hỏi đáp.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Bỏ, không lưu', style: TextStyle(color: C.danger)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: const Text('Họp tiếp')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Lưu')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'save') {
      await _finish();
    } else if (choice == 'discard') {
      await c.discard();
      _leaving = true;
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// The language pill: what captions are translated into, and what
  /// "Phát biểu" speaks to the room.
  Future<void> _pickLanguages() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ngôn ngữ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  const SectionLabel('Phụ đề dịch sang · bạn đọc'),
                  PillChoices<Lang>(
                    key: const Key('lang-target'),
                    values: Lang.values,
                    selected: c.target,
                    label: (l) => l.viTitle,
                    onChanged: c.state == LiveState.finished ? null : c.setTarget,
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('Chỉ hiện câu nói bằng'),
                  const SizedBox(height: 20),
                  const SectionLabel('Chỉ hiện câu nói bằng'),
                  PillChoices<Lang?>(
                    key: const Key('lang-filter'),
                    values: const [null, ...Lang.values],
                    selected: _spoken,
                    label: (l) => l?.viTitle ?? 'Tất cả',
                    onChanged: (l) {
                      setState(() => _spoken = l);
                      setSheet(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void _explain(int i) {
    final ai = c.textAi;
    if (ai == null) return;
    final all = c.sentences;
    showExplainSheet(
      context,
      ai: ai,
      sentence: all[i],
      readingLang: c.target,
      recent: all.sublist(i - 6 < 0 ? 0 : i - 6, i),
      meetingContext: c.context,
    );
  }

  (String, bool) get _statusLine => switch (c.state) {
    LiveState.idle || LiveState.starting => (_resuming ? 'Đang tiếp tục…' : 'Đang kết nối…', false),
    LiveState.live => ('Đang nghe…', true),
    LiveState.pausing => ('Đang dịch nốt câu cuối…', false),
    LiveState.paused => ('Đã tạm dừng', false),
    LiveState.finishing => ('Đang lưu…', false),
    LiveState.finished => ('Đã kết thúc', false),
    LiveState.failed => ('Không bắt đầu được', false),
  };

  /// "● Đang ghi · 12:48" on soft red while recording; grey otherwise.
  Widget _status() {
    final clock = formatClock(c.recorded);
    final live = c.state == LiveState.live;
    final text = switch (c.state) {
      LiveState.live => 'Đang ghi · $clock',
      LiveState.paused => 'Tạm dừng · $clock',
      LiveState.starting when _resuming => 'Đang tiếp tục…',
      _ => _statusLine.$1,
    };
    final fg = live ? C.danger : C.inkMuted;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: live ? C.dangerSoft : C.sunken, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              key: const Key('meeting-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = c.state;
    final all = c.sentences;
    final shown = visibleIndexes(all, _spoken);
    final liveSource = c.liveSource;
    final liveTranslation = c.liveTranslation;
    final showPending =
        (liveSource.isNotEmpty || liveTranslation.isNotEmpty) &&
        (_spoken == null || _spoken == (liveSource.isEmpty ? null : guessLang(liveSource)));
    final transitioning = state == LiveState.starting || state == LiveState.pausing || state == LiveState.finishing;
    final (status, active) = _statusLine;

    return PopScope(
      canPop: _leaving || state == LiveState.finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: C.surface,
          centerTitle: false,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Quay lại',
            icon: const Icon(Icons.chevron_left_rounded, size: 30, color: C.brand),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Align(alignment: Alignment.centerLeft, child: _status()),
          actions: [
            RoundIconButton(
              key: const Key('read-aloud'),
              icon: c.readAloud ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              tooltip: c.readAloud ? 'Đọc to bản dịch: đang bật' : 'Đọc to bản dịch: đang tắt',
              on: c.readAloud,
              onPressed: () => c.setReadAloud(!c.readAloud),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            if (c.notice != null) NoticeBar(text: c.notice!),
            if (Services.of(context).demoMode)
              const NoticeBar(
                key: Key('demo-notice'),
                text: 'Chế độ thử: câu nói là kịch bản mẫu; micro và loa vẫn chạy thật.',
              ),
            Container(
              decoration: const BoxDecoration(
                color: C.surface,
                border: Border(bottom: BorderSide(color: C.hairline)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  _LangPill(
                    target: c.target,
                    filter: _spoken,
                    onPressed: state == LiveState.finished ? null : _pickLanguages,
                  ),
                  const Spacer(),
                  ViewSegmented(view: _view, onView: (v) => setState(() => _view = v)),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  // The newest line sits at the bottom, as in SCOAI Voice:
                  // a short meeting hangs above the dock instead of
                  // leaving a gap under the captions.
                  CustomScrollView(
                    key: const Key('meeting-captions'),
                    controller: _scroll,
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (all.isNotEmpty && shown.isEmpty)
                                Padding(
                                  key: const Key('spoken-none'),
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                  child: Text(
                                    'Chưa có câu nào bằng ${_spoken!.viName}.',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              for (final i in shown)
                                MeetingCaption(
                                  key: ValueKey('caption-$i'),
                                  sentence: all[i],
                                  view: _view,
                                  onMark: () => c.toggleMark(i),
                                  onTap: c.textAi == null ? null : () => _explain(i),
                                ),
                              if (showPending)
                                PendingCaption(
                                  source: liveSource,
                                  translation: liveTranslation,
                                  target: c.target,
                                  view: _view,
                                ),
                              if (state != LiveState.finished) ListeningLine(text: status, active: active),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_awayFromLatest)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Center(child: JumpToLatest(onPressed: _toLatest)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.paddingOf(context).bottom),
              child: Row(
                children: [
                  Expanded(
                    child: MeetingCapsule(
                      paused: state == LiveState.paused,
                      resuming: _resuming && state == LiveState.starting,
                      onPauseResume:
                          transitioning ||
                              state == LiveState.failed ||
                              state == LiveState.finished ||
                              state == LiveState.idle
                          ? null
                          : _pauseOrResume,
                      onFinish: transitioning || state == LiveState.finished || state == LiveState.idle
                          ? null
                          : _finish,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _DockAction(
                    buttonKey: const Key('quick-ask'),
                    icon: Icons.auto_awesome,
                    label: 'Ask',
                    onPressed: c.textAi == null ? null : () => showAskSheet(context, c),
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

/// "Hỏi đáp" beside the capsule: an outlined pill with a label.
class _DockAction extends StatelessWidget {
  const _DockAction({required this.buttonKey, required this.icon, required this.label, required this.onPressed});

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const fg = C.brand;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Material(
        key: buttonKey,
        color: C.surface,
        shape: const StadiumBorder(side: BorderSide(color: C.brand, width: 1.4)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Opacity(
            opacity: onPressed == null ? 0.42 : 1,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 19, color: fg),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _pillText = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.ink);

/// "Việt ▾" in the top row: the language captions are translated into, and
/// the language filter when one is set. Opens the language sheet.
class _LangPill extends StatelessWidget {
  const _LangPill({required this.target, required this.onPressed, this.filter});
  final Lang target;
  final Lang? filter;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        'Dịch sang ${target.viName}'
        '${filter == null ? '' : ', chỉ hiện câu ${filter!.viName}'}',
    excludeSemantics: true,
    child: Material(
      key: const Key('languages'),
      color: C.surface,
      shape: const StadiumBorder(side: BorderSide(color: C.hairline)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.translate_rounded, size: 16, color: C.inkMuted),
              const SizedBox(width: 6),
              Text(target.short, style: _pillText),
              if (filter != null) ...[
                const SizedBox(width: 8),
                Container(
                  key: const Key('filter-badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: C.brandSoft, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.filter_list_rounded, size: 13, color: C.brand),
                      const SizedBox(width: 2),
                      Text(
                        filter!.short,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.brand),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 2),
              const Icon(Icons.expand_more_rounded, size: 18, color: C.inkMuted),
            ],
          ),
        ),
      ),
    ),
  );
}

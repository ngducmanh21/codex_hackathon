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
          roomSpeaker: s.roomSpeaker,
          store: s.library,
          target: widget.target,
          title: widget.title,
          context: widget.meetingContext,
          readAloud: widget.readAloud,
          textAi: s.textAi,
          awake: s.awake,
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
                  const SectionLabel('Phát biểu bằng · mọi người nghe'),
                  PillChoices<Lang?>(
                    key: const Key('lang-speak'),
                    values: [
                      null,
                      for (final l in Lang.values)
                        if (l != c.target) l,
                    ],
                    selected: c.replyLangChoice,
                    label: (l) => l?.viTitle ?? 'Tự động (${c.replyLang.short})',
                    onChanged: c.setReplyLang,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tự động: ngôn ngữ nghe thấy nhiều nhất gần đây.',
                    style: TextStyle(fontSize: 13, color: C.inkMuted),
                  ),
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
              key: const Key('quick-ask'),
              icon: Icons.contact_support_outlined,
              tooltip: 'Hỏi nhanh về cuộc họp',
              onPressed: c.textAi == null ? null : () => showAskSheet(context, c),
            ),
            const SizedBox(width: 8),
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
                    speak: c.replyLang,
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
            if (c.reply != null) _ReplyBanner(c: c),
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
                  _ReplyButton(
                    replying: c.replying,
                    lang: c.replyLang,
                    onPressed: state != LiveState.live || (c.reply != null && !c.replying)
                        ? null
                        : (c.replying ? c.endReply : c.startReply),
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

/// "Phát biểu": the user speaks in their language. Tap to start, tap again
/// when done; the phone then says the translation aloud to the room.
class _ReplyButton extends StatelessWidget {
  const _ReplyButton({required this.replying, required this.lang, required this.onPressed});
  final bool replying;
  final Lang lang;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: replying ? 'Xong, phát bằng ${lang.viName}' : 'Phát biểu bằng ${lang.viName}',
    excludeSemantics: true,
    child: Material(
      key: const Key('reply'),
      color: replying ? C.accent : C.surface,
      shape: CircleBorder(side: BorderSide(color: replying ? C.accent : C.brand, width: 1.5)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Opacity(
          opacity: onPressed == null ? 0.45 : 1,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      replying ? Icons.send_rounded : Icons.record_voice_over_outlined,
                      color: replying ? Colors.white : C.brand,
                      size: 20,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      replying ? 'Xong' : 'Phát biểu',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 12,
                        height: 14 / 12,
                        fontWeight: FontWeight.w700,
                        color: replying ? Colors.white : C.brand,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// What the user is saying and its translation, while they reply.
class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.c});
  final MeetingController c;

  @override
  Widget build(BuildContext context) {
    final r = c.reply!;
    return Container(
      key: const Key('reply-banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.listening ? 'Bạn đang phát biểu → ${c.replyLang.viName}' : 'Đang phát bằng ${c.replyLang.viName}…',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.accent),
          ),
          if (r.source.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.source.trim(),
              style: const TextStyle(fontSize: 15, height: 22 / 15, color: C.inkMuted),
            ),
          ],
          if (r.translation.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              r.translation.trim(),
              style: const TextStyle(fontSize: 20, height: 30 / 20, color: C.ink),
            ),
          ],
          if (r.source.trim().isEmpty && r.listening)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Nói ${c.target.viName}, xong bấm Xong để phát cho mọi người nghe.',
                style: const TextStyle(fontSize: 14, color: C.inkMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Việt ⇄ Trung" in the top bar: captions in the first, "Phát biểu" in the
/// second. Opens the language sheet.
const _pillText = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.ink);

class _LangPill extends StatelessWidget {
  const _LangPill({required this.target, required this.speak, required this.onPressed, this.filter});
  final Lang target;
  final Lang speak;
  final Lang? filter;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        'Ngôn ngữ: phụ đề ${target.viName}, phát biểu ${speak.viName}'
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
              Text(target.short, style: _pillText),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.swap_horiz_rounded, size: 16, color: C.inkMuted),
              ),
              Text(speak.short, style: _pillText),
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

import 'package:flutter/material.dart';

import '../domain/lang.dart';
import '../domain/records.dart';
import '../domain/segmenter.dart';
import 'theme.dart';

/// What each caption shows, as in SCOAI Voice's meeting screen: the words
/// as spoken small above their translation, only the words as spoken, or
/// only the translation.
enum CaptionView {
  both('Cả hai'),
  original('Gốc'),
  translation('Dịch');

  const CaptionView(this.label);
  final String label;
}

/// Chinese speech gets SCOAI's soft orange; Vietnamese and English the navy.
({Color bg, Color fg}) langColors(Lang? lang) =>
    lang == Lang.zh ? (bg: const Color(0xFFFDEEE4), fg: const Color(0xFF9A3E0A)) : (bg: C.brandSoft, fg: C.brand);

/// "● Trung": the language a sentence was spoken in.
class LangTag extends StatelessWidget {
  const LangTag(this.lang, {super.key});
  final Lang? lang;

  @override
  Widget build(BuildContext context) {
    final c = langColors(lang);
    return Semantics(
      label: lang == null ? 'Chưa rõ ngôn ngữ' : 'Nói ${lang!.viName}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: ShapeDecoration(
          color: c.bg,
          shape: StadiumBorder(side: BorderSide(color: c.fg.withValues(alpha: 0.22))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              lang?.short ?? '?',
              style: TextStyle(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w700, color: c.fg),
            ),
          ],
        ),
      ),
    );
  }
}

const _smallStyle = TextStyle(fontSize: 15, height: 22 / 15, color: C.inkMuted);
const _bigStyle = TextStyle(fontSize: 20, height: 30 / 20, color: C.ink);

/// The big line with the speaker's colour bar on its left.
class _Barred extends StatelessWidget {
  const _Barred({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            child: const SizedBox(width: 3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    ),
  );
}

Widget _tagged(Lang? lang, String text, TextStyle style, {Key? key, bool you = false}) => Text.rich(
  TextSpan(
    children: [
      if (you)
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(padding: EdgeInsets.only(right: 6), child: YouTag()),
        ),
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(padding: const EdgeInsets.only(right: 8), child: LangTag(lang)),
      ),
      TextSpan(text: text),
    ],
  ),
  key: key,
  style: style,
);

/// "Bạn": a line the user said with "Tôi trả lời".
class YouTag extends StatelessWidget {
  const YouTag({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: const ShapeDecoration(color: C.accent, shape: StadiumBorder()),
    child: const Text(
      'Bạn',
      style: TextStyle(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w700, color: Colors.white),
    ),
  );
}

/// One finished sentence of a meeting.
///
/// With a translation: tag and original small and grey, the translation
/// large beside the colour bar. Spoken in the language shown: one large
/// line. The flag on the right marks it.
class MeetingCaption extends StatelessWidget {
  const MeetingCaption({super.key, required this.sentence, required this.view, this.onMark, this.onTap, this.time});

  final Sentence sentence;
  final CaptionView view;
  final VoidCallback? onMark;

  /// Opens "Giải thích".
  final VoidCallback? onTap;

  /// Shown in the saved transcript (Q&A cites times), not while live.
  final String? time;

  @override
  Widget build(BuildContext context) {
    final s = sentence;
    final translated = s.hasTranslation;
    final String? small;
    final String big;
    switch (view) {
      case CaptionView.original:
        small = null;
        big = s.source;
      case CaptionView.translation:
        small = null;
        big = translated ? s.translation : s.source;
      case CaptionView.both:
        small = translated ? s.source : null;
        big = translated ? s.translation : s.source;
    }
    final you = s.speaker == 0;
    final bar = you ? C.accent : langColors(s.lang).fg;
    final timePrefix = time == null ? '' : '$time  ';
    return Semantics(
      container: true,
      label: '${you ? 'Bạn trả lời' : s.lang?.viName ?? ''}. ${s.source}${translated ? '. ${s.translation}' : ''}',
      onTapHint: onTap == null ? null : 'Giải thích',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (small != null) ...[
                      _tagged(s.lang, '$timePrefix$small', _smallStyle, key: const Key('caption-small'), you: you),
                      const SizedBox(height: 4),
                      _Barred(
                        color: bar,
                        child: Text(big, key: const Key('caption-big'), style: _bigStyle),
                      ),
                    ] else
                      _Barred(
                        color: bar,
                        child: _tagged(s.lang, big, _bigStyle, key: const Key('caption-big'), you: you),
                      ),
                    if (small == null && time != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 13, top: 2),
                        child: Text(time!, style: const TextStyle(fontSize: 12, color: C.inkMuted)),
                      ),
                  ],
                ),
              ),
            ),
            if (onMark != null)
              IconButton(
                tooltip: s.marked ? 'Bỏ đánh dấu' : 'Đánh dấu',
                onPressed: onMark,
                icon: Icon(
                  s.marked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: s.marked ? C.accent : C.inkMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The sentence still being spoken or translated.
class PendingCaption extends StatelessWidget {
  const PendingCaption({
    super.key,
    required this.source,
    required this.translation,
    required this.target,
    required this.view,
  });

  final String source;
  final String translation;
  final Lang target;
  final CaptionView view;

  @override
  Widget build(BuildContext context) {
    final lang = guessLang(source);
    final sameLanguage = lang == target;
    final bar = langColors(lang).fg;
    final draft = TextStyle(fontSize: 20, height: 30 / 20, color: C.ink.withValues(alpha: 0.55));
    final Widget body;
    if (view == CaptionView.original || sameLanguage || source.isEmpty) {
      body = _Barred(color: bar, child: _tagged(lang, source.isEmpty ? translation : source, draft));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (view == CaptionView.both || translation.isEmpty) _tagged(lang, source, _smallStyle),
          const SizedBox(height: 4),
          if (translation.isNotEmpty)
            _Barred(
              color: bar,
              child: Text('$translation…', style: draft),
            )
          else
            const Padding(
              padding: EdgeInsets.only(left: 13),
              child: Text('Đang dịch…', key: Key('caption-pending'), style: _smallStyle),
            ),
        ],
      );
    }
    return Padding(key: const Key('pending-caption'), padding: const EdgeInsets.fromLTRB(16, 10, 52, 10), child: body);
  }
}

/// "● Đang nghe…" at the end of the captions, instead of an empty box.
class ListeningLine extends StatefulWidget {
  const ListeningLine({super.key, required this.text, required this.active});
  final String text;
  final bool active;

  @override
  State<ListeningLine> createState() => _ListeningLineState();
}

class _ListeningLineState extends State<ListeningLine> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ListeningLine old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final animate = widget.active && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!animate && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? C.danger : C.inkMuted;
    return Padding(
      key: const Key('listening-line'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.text,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cả hai | Gốc | Dịch, and the language filter.
class CaptionControls extends StatelessWidget {
  const CaptionControls({
    super.key,
    required this.view,
    required this.onView,
    required this.spoken,
    required this.onSpoken,
  });

  final CaptionView view;
  final ValueChanged<CaptionView> onView;
  final Lang? spoken;
  final ValueChanged<Lang?> onSpoken;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      children: [
        ViewSegmented(view: view, onView: onView),
        const Spacer(),
        Builder(
          builder: (anchor) => _Pill(
            key: const Key('spoken-filter'),
            selected: spoken != null,
            semanticLabel: 'Lọc theo ngôn ngữ nói: ${spoken?.viName ?? 'mọi ngôn ngữ'}',
            onTap: () => _pick(anchor),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.filter_list_rounded, size: 18, color: spoken != null ? Colors.white : C.ink),
                if (spoken != null) ...[const SizedBox(width: 4), Text(spoken!.short)],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _pick(BuildContext anchor) async {
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(anchor).context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    PopupMenuItem<String> item(String value, String label, bool on) => PopupMenuItem<String>(
      key: Key('spoken-$value'),
      value: value,
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (on) const Icon(Icons.check, size: 20, color: C.brand),
        ],
      ),
    );
    final picked = await showMenu<String>(
      context: anchor,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        item('all', 'Mọi ngôn ngữ', spoken == null),
        for (final l in Lang.values) item(l.code, l.viTitle, spoken == l),
      ],
    );
    if (picked == null) return;
    onSpoken(picked == 'all' ? null : Lang.fromCode(picked));
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.selected, required this.onTap, required this.child, this.semanticLabel});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: semanticLabel,
    child: Material(
      color: selected ? C.brand : C.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? C.brand : C.hairline)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? Colors.white : C.ink,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Cả hai | Gốc | Dịch as one segmented control, as in SCOAI Voice.
class ViewSegmented extends StatelessWidget {
  const ViewSegmented({super.key, required this.view, required this.onView});
  final CaptionView view;
  final ValueChanged<CaptionView> onView;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Hiện phụ đề',
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: C.brandSoft, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in CaptionView.values)
            Semantics(
              button: true,
              selected: v == view,
              child: Material(
                key: Key('view-${v.name}'),
                color: v == view ? C.brand : Colors.transparent,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onView(v),
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    child: Text(
                      v.label,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: v == view ? FontWeight.w700 : FontWeight.w600,
                        color: v == view ? Colors.white : C.brand,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A 40 dp round icon button on a soft ground; filled navy when [on].
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.on = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool on;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      toggled: on,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        color: on ? C.brand : C.sunken,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 20, color: on ? Colors.white : C.brand)),
        ),
      ),
    ),
  );
}

/// "Mới nhất ↓" over the captions while the user reads older ones.
class JumpToLatest extends StatelessWidget {
  const JumpToLatest({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('jump-latest'),
    color: C.surface,
    elevation: 4,
    shadowColor: C.ink.withValues(alpha: 0.2),
    shape: const StadiumBorder(side: BorderSide(color: C.hairline)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onPressed,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mới nhất',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.brand),
            ),
            SizedBox(width: 6),
            Icon(Icons.arrow_downward_rounded, size: 18, color: C.brand),
          ],
        ),
      ),
    ),
  );
}

/// SCOAI's orange capsule: "Pause" (or "Resume") on the left and a white
/// "Stop" half on the right.
class MeetingCapsule extends StatelessWidget {
  const MeetingCapsule({
    super.key,
    required this.paused,
    required this.resuming,
    required this.onPauseResume,
    required this.onFinish,
  });

  final bool paused;
  final bool resuming;
  final VoidCallback? onPauseResume;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    final label = resuming ? 'Resuming…' : (paused ? 'Resume' : 'Pause');
    final icon = resuming ? Icons.hourglass_top_rounded : (paused ? Icons.play_arrow_rounded : Icons.pause_rounded);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: accentGradient, borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const Key('pause-resume'),
                  customBorder: const StadiumBorder(),
                  onTap: onPauseResume,
                  child: Opacity(
                    opacity: onPauseResume == null ? 0.6 : 1,
                    child: SizedBox(
                      height: 52,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: Colors.white),
                          const SizedBox(width: 8),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                maxLines: 1,
                                textScaler: TextScaler.noScaling,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Material(
              color: C.surface,
              shape: const StadiumBorder(),
              child: InkWell(
                key: const Key('finish'),
                customBorder: const StadiumBorder(),
                onTap: onFinish,
                child: Opacity(
                  opacity: onFinish == null ? 0.5 : 1,
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(color: C.danger, borderRadius: BorderRadius.circular(4)),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Stop',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Indexes of [sentences] spoken in [spoken] (all when null).
List<int> visibleIndexes(List<Sentence> sentences, Lang? spoken) => [
  for (var i = 0; i < sentences.length; i++)
    if (spoken == null || sentences[i].lang == spoken) i,
];

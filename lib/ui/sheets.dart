import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/lang.dart';
import '../domain/records.dart';
import '../live/meeting_controller.dart' show describeError, MeetingController;
import '../openai/text_ai.dart';
import 'captions.dart';
import 'theme.dart';

/// "Giải thích": what a sentence means, its tone and replies to give.
Future<void> showExplainSheet(
  BuildContext context, {
  required TextAi ai,
  required Sentence sentence,
  required Lang readingLang,
  List<Sentence> recent = const [],
  MeetingContext meetingContext = const MeetingContext(),
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: C.paper,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) => _ExplainBody(
          scroll: scroll,
          future: ai.explain(sentence, readingLang: readingLang, recent: recent, context: meetingContext),
          sentence: sentence,
        ),
      ),
    );

class _ExplainBody extends StatelessWidget {
  const _ExplainBody({required this.scroll, required this.future, required this.sentence});
  final ScrollController scroll;
  final Future<Explanation> future;
  final Sentence sentence;

  @override
  Widget build(BuildContext context) => FutureBuilder<Explanation>(
        future: future,
        builder: (context, snap) {
          final children = <Widget>[
            Row(children: [
              LangTag(sentence.lang),
              const SizedBox(width: 8),
              const Text('Giải thích', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            Text(sentence.source, style: const TextStyle(fontSize: 16, height: 24 / 16, color: C.inkMuted)),
            const SizedBox(height: 16),
          ];
          if (snap.connectionState != ConnectionState.done) {
            children.add(const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ));
          } else if (snap.hasError) {
            children.add(Text(describeError(snap.error!), style: const TextStyle(color: C.danger)));
          } else {
            final x = snap.data!;
            children
              ..add(const _Heading('Ý nghĩa'))
              ..add(SelectableText(x.meaning, style: const TextStyle(fontSize: 17, height: 26 / 17)));
            if (x.nuance.trim().isNotEmpty) {
              children
                ..add(const SizedBox(height: 16))
                ..add(const _Heading('Sắc thái'))
                ..add(SelectableText(x.nuance, style: const TextStyle(fontSize: 16, height: 24 / 16)));
            }
            if (x.replies.isNotEmpty) {
              children
                ..add(const SizedBox(height: 16))
                ..add(const _Heading('Có thể đáp'));
              for (final r in x.replies) {
                children.add(Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: C.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: C.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.text, style: const TextStyle(fontSize: 18, height: 26 / 18, fontWeight: FontWeight.w600)),
                            if (r.translation.trim().isNotEmpty)
                              Text(r.translation, style: const TextStyle(fontSize: 14, color: C.inkMuted)),
                          ]),
                        ),
                        IconButton(
                          tooltip: 'Sao chép',
                          icon: const Icon(Icons.copy_rounded, color: C.inkMuted, size: 20),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: r.text));
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Đã sao chép')));
                          },
                        ),
                      ]),
                    ),
                  ),
                ));
              }
            }
          }
          return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: children);
        },
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.inkMuted)),
      );
}

/// "Hỏi nhanh" during a meeting: questions about what has been said.
Future<void> showAskSheet(BuildContext context, MeetingController c) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: C.paper,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _AskBody(c: c),
      ),
    );

class _AskBody extends StatefulWidget {
  const _AskBody({required this.c});
  final MeetingController c;
  @override
  State<_AskBody> createState() => _AskBodyState();
}

class _AskBodyState extends State<_AskBody> {
  final _q = TextEditingController();
  String? _error;

  static const suggestions = ['Họ vừa nói gì về giá?', 'Đã chốt những gì?', 'Còn chờ mình trả lời gì?'];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _ask(String q) async {
    final question = q.trim();
    if (question.isEmpty || widget.c.asking) return;
    setState(() => _error = null);
    try {
      await widget.c.ask(question);
      _q.clear();
    } on Object catch (e) {
      _error = describeError(e);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.c,
        builder: (context, _) {
          final c = widget.c;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  children: [
                    const Text('Hỏi nhanh', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Trả lời từ những gì đã nói trong ${formatClock(c.recorded)} vừa qua.',
                        style: const TextStyle(fontSize: 13, color: C.inkMuted)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final s in suggestions)
                        ActionChip(
                          label: Text(s),
                          onPressed: c.asking || c.sentences.isEmpty ? null : () => _ask(s),
                          backgroundColor: C.surface,
                          side: const BorderSide(color: C.hairline),
                          shape: const StadiumBorder(),
                        ),
                    ]),
                    for (final qa in c.liveQa) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: const BoxDecoration(
                            color: C.brand,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(18),
                              bottomRight: Radius.circular(6),
                            ),
                          ),
                          child: Text(qa.question, style: const TextStyle(color: Colors.white, fontSize: 15)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: C.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: C.hairline),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SelectableText(qa.answer, style: const TextStyle(fontSize: 16, height: 24 / 16)),
                          if (qa.refs.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Lúc ${qa.refs.join(', ')}', style: const TextStyle(fontSize: 12, color: C.inkMuted)),
                            ),
                        ]),
                      ),
                    ],
                    if (c.asking) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: C.danger))),
                    if (c.sentences.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('Chưa có câu nào để hỏi.', style: TextStyle(color: C.inkMuted)),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        key: const Key('ask-input'),
                        controller: _q,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _ask,
                        decoration: InputDecoration(
                          hintText: 'Hỏi về cuộc họp đang diễn ra',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: C.hairline)),
                          enabledBorder:
                              OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: C.hairline)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      tooltip: 'Gửi',
                      style: IconButton.styleFrom(backgroundColor: C.brand, fixedSize: const Size(48, 48)),
                      onPressed: c.asking || c.sentences.isEmpty ? null : () => _ask(_q.text),
                      icon: const Icon(Icons.arrow_upward, color: Colors.white),
                    ),
                  ]),
                ),
              ),
            ]),
          );
        },
      );
}

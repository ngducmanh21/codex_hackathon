import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app/services.dart';
import '../domain/lang.dart';
import '../domain/records.dart';
import '../live/meeting_controller.dart' show describeError;
import '../share/minutes.dart';
import 'captions.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets.dart';

/// A saved meeting, dialogue or upload: Tóm tắt / Bản ghi / Hỏi đáp.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key, required this.itemId, this.autoSummarize = false});
  final String itemId;
  final bool autoSummarize;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  final _question = TextEditingController();
  LibraryItem? _item;
  bool _loading = true;
  bool _summarizing = false;
  bool _asking = false;
  String? _error;
  bool _started = false;
  CaptionView _view = CaptionView.both;
  Lang? _spoken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _question.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final item = await Services.of(context).library.get(widget.itemId);
    if (!mounted) return;
    setState(() {
      _item = item;
      _loading = false;
    });
    if (item != null && item.summary == null && widget.autoSummarize && item.sentences.isNotEmpty) {
      _summarize();
    }
  }

  Lang get _readingLang {
    final i = _item!;
    return i.kind == ItemKind.dialogue ? (i.sourceLang ?? Lang.vi) : i.targetLang;
  }

  Future<void> _update(LibraryItem next) async {
    final s = Services.of(context);
    await s.library.save(next);
    s.libraryChanged();
    if (mounted) setState(() => _item = next);
  }

  Future<void> _summarize() async {
    setState(() {
      _summarizing = true;
      _error = null;
    });
    try {
      final summary = await Services.of(context).textAi.summarize(_item!, readingLang: _readingLang);
      if (!mounted) return;
      await _update(_item!.copyWith(summary: summary));
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<void> _ask(String q) async {
    final question = q.trim();
    if (question.isEmpty || _asking) return;
    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      final qa = await Services.of(context).textAi.ask(_item!, question);
      if (!mounted) return;
      _question.clear();
      await _update(_item!.copyWith(qa: [..._item!.qa, qa]));
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  /// Sends the minutes to Zalo, Messenger, e-mail… through Android's share.
  Future<void> _share() async {
    final item = _item!;
    final withTranscript = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Chia sẻ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              key: const Key('share-summary'),
              leading: const Icon(Icons.summarize_outlined),
              title: const Text('Biên bản'),
              subtitle: Text(
                item.summary == null ? 'Chưa có tóm tắt: gửi kèm bản ghi' : 'Tóm tắt, đã chốt, việc cần làm',
              ),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              key: const Key('share-all'),
              leading: const Icon(Icons.article_outlined),
              title: const Text('Biên bản và bản ghi song ngữ'),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (withTranscript == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text: minutesText(item, withTranscript: withTranscript),
        subject: item.title,
      ),
    );
  }

  void _explain(LibraryItem item, int i) {
    final s = item.sentences[i];
    showExplainSheet(
      context,
      ai: Services.of(context).textAi,
      sentence: s,
      readingLang: _readingLang,
      recent: item.sentences.sublist(i - 6 < 0 ? 0 : i - 6, i),
      meetingContext: item.context,
    );
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _item!.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Lưu')),
        ],
      ),
    );
    c.dispose();
    if (name != null && name.trim().isNotEmpty) await _update(_item!.copyWith(title: name.trim()));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá mục này?'),
        content: const Text('Bản ghi, tóm tắt và hỏi đáp sẽ bị xoá khỏi máy.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = Services.of(context);
    await s.library.delete(_item!.id);
    s.libraryChanged();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final item = _item;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Không tìm thấy mục này.')),
      );
    }
    final langs = item.kind == ItemKind.dialogue
        ? '${item.sourceLang?.label ?? ''} ⇄ ${item.targetLang.label}'
        : '→ ${item.targetLang.label}';
    final t = item.createdAt;
    final when =
        '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.paper,
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.chevron_left_rounded, size: 30, color: C.brand),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Thêm',
            onSelected: (v) => v == 'rename' ? _rename() : _delete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Đổi tên')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Xoá', style: TextStyle(color: C.danger)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(fontSize: 24, height: 31 / 24, fontWeight: FontWeight.w700, color: C.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  '$when · ${formatClock(item.duration)} · $langs',
                  style: const TextStyle(fontSize: 13, color: C.inkMuted),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: C.brand,
            unselectedLabelColor: C.inkMuted,
            indicatorColor: C.brand,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            tabs: const [
              Tab(text: 'Tóm tắt'),
              Tab(text: 'Bản ghi'),
              Tab(text: 'Hỏi đáp'),
            ],
          ),
          if (_error != null) NoticeBar(text: _error!),
          Expanded(
            child: TabBarView(controller: _tabs, children: [_summaryTab(item), _transcriptTab(item), _qaTab(item)]),
          ),
          if (_tabs.index != 2) _bottomBar(),
        ],
      ),
    );
  }

  /// TwinMind's bottom pair: a dark "Chia sẻ" pill and an outlined
  /// "Hỏi về cuộc họp".
  Widget _bottomBar() => Container(
    decoration: const BoxDecoration(
      color: C.paper,
      border: Border(top: BorderSide(color: C.hairline)),
    ),
    padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
    child: Row(
      children: [
        Material(
          key: const Key('share'),
          color: C.brand,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _share,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.share_outlined, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Chia sẻ',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinePill(
            key: const Key('go-qa'),
            label: 'Hỏi về cuộc họp',
            icon: Icons.auto_awesome,
            onPressed: () => _tabs.animateTo(2),
          ),
        ),
      ],
    ),
  );

  Widget _summaryTab(LibraryItem item) {
    final s = item.summary;
    if (s == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _summarizing
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Đang tóm tắt…')],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.sentences.isEmpty ? 'Không có nội dung để tóm tắt.' : 'Chưa có tóm tắt.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    if (item.sentences.isNotEmpty)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: C.brand,
                          minimumSize: const Size(0, 48),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _summarize,
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Tạo tóm tắt'),
                      ),
                  ],
                ),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        SelectableText(s.overview, style: text.bodyLarge),
        if (s.decisions.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Đã chốt', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final d in s.decisions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(fontSize: 15)),
                  Expanded(child: SelectableText(d, style: text.bodyMedium)),
                ],
              ),
            ),
        ],
        if (s.actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Việc cần làm', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < s.actions.length; i++)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      border: i == s.actions.length - 1 ? null : const Border(bottom: BorderSide(color: C.hairline)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.actions[i].task, style: text.bodyMedium),
                        if (s.actions[i].owner.isNotEmpty || s.actions[i].due.isNotEmpty)
                          Text(
                            [s.actions[i].owner, s.actions[i].due].where((x) => x.isNotEmpty).join(' · '),
                            style: text.bodySmall,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (s.openQuestions.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Còn bỏ ngỏ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final q in s.openQuestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(fontSize: 15)),
                  Expanded(child: SelectableText(q, style: text.bodyMedium)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: _summarizing ? null : _summarize,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tóm tắt lại'),
          ),
        ),
      ],
    );
  }

  Widget _transcriptTab(LibraryItem item) {
    if (item.sentences.isEmpty) return const Center(child: Text('Không có câu nào.'));
    final shown = visibleIndexes(item.sentences, _spoken);
    final showTime = item.kind != ItemKind.upload;
    return Column(
      children: [
        const SizedBox(height: 10),
        CaptionControls(
          view: _view,
          onView: (v) => setState(() => _view = v),
          spoken: _spoken,
          onSpoken: (l) => setState(() => _spoken = l),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: shown.length,
            itemBuilder: (_, k) {
              final i = shown[k];
              final s = item.sentences[i];
              final caption = MeetingCaption(
                sentence: s,
                view: _view,
                time: showTime ? formatClock(s.at) : '#${i + 1}',
                onTap: () => _explain(item, i),
                onMark: () => _update(
                  item.copyWith(
                    sentences: [
                      for (var j = 0; j < item.sentences.length; j++)
                        j == i ? s.copyWith(marked: !s.marked) : item.sentences[j],
                    ],
                  ),
                ),
              );
              if (s.speaker == null) return caption;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Text(
                      s.speaker == 0 ? 'Tôi' : 'Người kia',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.brand),
                    ),
                  ),
                  caption,
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _qaTab(LibraryItem item) {
    const suggestions = ['Đã chốt những gì?', 'Ai làm việc gì?', 'Còn gì chưa rõ?'];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(s),
                      onPressed: _asking ? null : () => _ask(s),
                      backgroundColor: C.surface,
                      side: const BorderSide(color: C.hairline),
                      shape: const StadiumBorder(),
                    ),
                ],
              ),
              for (final qa in item.qa) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
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
                const SizedBox(height: 10),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(qa.answer, style: Theme.of(context).textTheme.bodyMedium),
                      if (qa.refs.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('Trong bản ghi:', style: TextStyle(fontSize: 12, color: C.inkMuted)),
                            for (final r in qa.refs)
                              ActionChip(
                                label: Text(
                                  r,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.brand),
                                ),
                                onPressed: () => _tabs.animateTo(1),
                                backgroundColor: C.sunken,
                                side: BorderSide.none,
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_asking)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: C.surface,
            border: Border(top: BorderSide(color: C.hairline)),
          ),
          padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _question,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _ask,
                  decoration: InputDecoration(
                    hintText: 'Hỏi về cuộc họp này',
                    fillColor: C.paper,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: C.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: C.hairline),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                tooltip: 'Gửi',
                style: IconButton.styleFrom(backgroundColor: C.brand, fixedSize: const Size(48, 48)),
                onPressed: _asking ? null : () => _ask(_question.text),
                icon: const Icon(Icons.arrow_upward, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

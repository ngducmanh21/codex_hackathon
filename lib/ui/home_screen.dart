import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/records.dart';
import 'logo.dart';
import 'meeting_setup_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'upload_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<LibraryItem> _items = const [];
  bool _loading = true;
  bool _hasKey = true;
  ItemKind? _filter;
  String _query = '';
  AppServices? _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = Services.of(context);
    if (!identical(s, _services)) {
      _services?.libraryVersion.removeListener(_reload);
      _services = s;
      s.libraryVersion.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _services?.libraryVersion.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final s = _services!;
    final items = await s.library.list();
    final hasKey = await s.hasKey();
    if (!mounted) return;
    setState(() {
      _items = items;
      _hasKey = hasKey;
      _loading = false;
    });
  }

  List<LibraryItem> get _visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final i in _items)
        if ((_filter == null || i.kind == _filter) &&
            (q.isEmpty ||
                i.title.toLowerCase().contains(q) ||
                i.sentences.any((s) => s.source.toLowerCase().contains(q) || s.translation.toLowerCase().contains(q))))
          i,
    ];
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        // SCOAI Voice's home bar: the logo on a white pill.
        title: Align(
          alignment: Alignment.centerLeft,
          child: DecoratedBox(
            decoration: const ShapeDecoration(color: C.surface, shape: StadiumBorder()),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: FittedBox(fit: BoxFit.scaleDown, child: ScoaiLogo()),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Cài đặt',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _open(const SettingsScreen()),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        if (!_hasKey && !_loading)
          NoticeBar(
            text: 'Chưa có khoá OpenAI. Thêm khoá để bắt đầu.',
            action: 'Thêm khoá',
            onAction: () => _open(const SettingsScreen()),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Tìm trong Thư viện',
              prefixIcon: const Icon(Icons.search, color: C.inkMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: C.hairline)),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: C.hairline)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(children: [
            Text('Thư viện', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Text('${_items.length} mục', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              PillChoices<ItemKind?>(
                values: const [null, ItemKind.meeting, ItemKind.upload],
                selected: _filter,
                label: (k) => switch (k) {
                  null => 'Tất cả',
                  ItemKind.meeting => 'Cuộc họp',
                  ItemKind.dialogue => 'Hội thoại',
                  ItemKind.upload => 'Tải lên',
                },
                onChanged: (k) => setState(() => _filter = k),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _items.isEmpty
                            ? 'Chưa có mục nào. Bắt đầu một cuộc họp hoặc tải tệp âm thanh lên.'
                            : 'Không có mục khớp.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ItemRow(
                        item: visible[i],
                        onTap: () => _open(SavedScreen(itemId: visible[i].id)),
                      ),
                    ),
        ),
        _StartDock(
          onMeeting: () => _open(const MeetingSetupScreen()),
          onUpload: () => _open(const UploadScreen()),
        ),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});
  final LibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.kind) {
      ItemKind.meeting => Icons.groups_outlined,
      ItemKind.dialogue => Icons.forum_outlined,
      ItemKind.upload => Icons.upload_file_outlined,
    };
    final langs = item.kind == ItemKind.dialogue
        ? '${item.sourceLang?.label ?? ''} ⇄ ${item.targetLang.label}'
        : '${item.sourceLang?.label ?? _spoken(item)} → ${item.targetLang.label}';
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: C.brandSoft, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: C.brand, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(
              '${_day(item.createdAt)} · ${_minutes(item.duration)} · $langs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      ]),
    );
  }
}

String _spoken(LibraryItem i) {
  final langs = {for (final s in i.sentences) if (s.lang != null && s.lang != i.targetLang) s.lang!};
  return langs.isEmpty ? '…' : langs.map((l) => l.label).join('/');
}

String _day(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  if (d == today) return 'Hôm nay';
  if (d == today.subtract(const Duration(days: 1))) return 'Hôm qua';
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
}

String _minutes(Duration d) => d.inMinutes < 1 ? '${d.inSeconds} giây' : '${d.inMinutes} phút';

class _StartDock extends StatelessWidget {
  const _StartDock({required this.onMeeting, required this.onUpload});
  final VoidCallback onMeeting;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: C.paper, border: Border(top: BorderSide(color: C.hairline))),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
        child: Column(children: [
          AccentButton(key: const Key('start-meeting'), label: 'Bắt đầu cuộc họp', icon: Icons.mic_none, onPressed: onMeeting),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinePill(label: 'Tải âm thanh lên', icon: Icons.upload, onPressed: onUpload),
          ),
        ]),
      );
}

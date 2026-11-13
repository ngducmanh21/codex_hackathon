import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/records.dart';
import 'home_screen.dart' show dayLabel, minutesLabel;
import 'saved_screen.dart';
import 'theme.dart';

/// The saved items, after TwinMind's "Memories": a search field, filter
/// chips, and the items grouped under a date heading.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<LibraryItem> _items = const [];
  bool _loading = true;
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
    final items = await _services!.library.list();
    if (!mounted) return;
    setState(() {
      _items = items;
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

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    // Group by day, keeping the order (newest first).
    final groups = <String, List<LibraryItem>>{};
    for (final i in visible) {
      groups.putIfAbsent(dayLabel(i.createdAt), () => []).add(i);
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.paper,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.chevron_left_rounded, size: 30, color: C.brand),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Thư viện',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: C.ink),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              key: const Key('library-search'),
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Tìm trong Thư viện',
                prefixIcon: const Icon(Icons.search_rounded, color: C.inkMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: const BorderSide(color: C.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: const BorderSide(color: C.hairline),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final k in const [null, ItemKind.meeting, ItemKind.upload])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(
                      label: switch (k) {
                        null => 'Tất cả',
                        ItemKind.meeting => 'Cuộc họp',
                        ItemKind.upload => 'Tải lên',
                        ItemKind.dialogue => 'Hội thoại',
                      },
                      selected: _filter == k,
                      onTap: () => setState(() => _filter = k),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _items.isEmpty ? 'Chưa có mục nào.' : 'Không có mục nào khớp.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, color: C.inkMuted),
                      ),
                    ),
                  )
                : ListView(
                    key: const Key('library-list'),
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 14, 0, 8),
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.inkMuted),
                          ),
                        ),
                        for (final item in entry.value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ItemCard(
                              item: item,
                              onTap: () async {
                                await Navigator.of(
                                  context,
                                ).push(MaterialPageRoute<void>(builder: (_) => SavedScreen(itemId: item.id)));
                                _reload();
                              },
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? C.brandSoft : C.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? C.brand : C.hairline)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? C.brand : C.ink,
            ),
          ),
        ),
      ),
    ),
  );
}

/// One saved item: an icon tile, the title, and its time and languages.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, required this.onTap});
  final LibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.kind) {
      ItemKind.meeting => Icons.groups_outlined,
      ItemKind.dialogue => Icons.forum_outlined,
      ItemKind.upload => Icons.graphic_eq_rounded,
    };
    final langs = item.kind == ItemKind.dialogue
        ? '${item.sourceLang?.label ?? ''} ⇄ ${item.targetLang.label}'
        : '→ ${item.targetLang.label}';
    final t = item.createdAt;
    return Material(
      color: C.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: C.brandSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: C.brand),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} · ${minutesLabel(item.duration)} · $langs',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: C.inkMuted),
                    ),
                  ],
                ),
              ),
              if (item.summary != null) const Icon(Icons.auto_awesome, size: 15, color: C.accent),
            ],
          ),
        ),
      ),
    );
  }
}

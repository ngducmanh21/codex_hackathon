import 'package:flutter/material.dart';

import '../app/services.dart';
import '../calendar/calendar_source.dart';
import '../domain/records.dart';
import 'library_screen.dart';
import 'logo.dart';
import 'meeting_setup_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'upload_screen.dart';
import 'widgets.dart';

/// Home, after TwinMind: a sky header, the latest meeting as a card, the
/// library in two tiles, the phone's upcoming meetings, and one orange
/// button that starts recording.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<LibraryItem> _items = const [];
  List<UpcomingEvent> _events = const [];
  bool _loading = true;
  bool _hasKey = true;
  bool _calendarOn = false;
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
    final cal = s.calendar;
    final on = cal != null && await cal.hasPermission();
    final events = on ? await cal.upcoming() : const <UpcomingEvent>[];
    if (!mounted) return;
    setState(() {
      _items = items;
      _hasKey = hasKey;
      _calendarOn = on;
      _events = events;
      _loading = false;
    });
  }

  Future<void> _askCalendar() async {
    final cal = _services?.calendar;
    if (cal == null) return;
    await cal.requestPermission();
    await _reload();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    _reload();
  }

  int _count(ItemKind kind) => _items.where((i) => i.kind == kind).length;

  @override
  Widget build(BuildContext context) {
    final latest = _items.isEmpty ? null : _items.first;
    final demo = _services?.demoMode ?? false;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: skyGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _header(),
              if (demo)
                NoticeBar(
                  key: const Key('demo-banner'),
                  text: 'Chế độ thử: dữ liệu mẫu, không gọi OpenAI.',
                  action: 'Tắt',
                  onAction: () => _services!.setDemoMode(false),
                )
              else if (!_hasKey && !_loading)
                NoticeBar(
                  text: 'Chưa có khoá OpenAI.',
                  action: 'Thêm khoá',
                  onAction: () => _open(const SettingsScreen()),
                  action2: 'Dùng thử',
                  onAction2: () => _services!.setDemoMode(true),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : ListView(
                        key: const Key('home-list'),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        children: [
                          if (latest != null)
                            _LatestCard(
                              item: latest,
                              onTap: () => _open(SavedScreen(itemId: latest.id)),
                            )
                          else
                            const _EmptyCard(),
                          const SizedBox(height: 18),
                          _SectionLabel(
                            'Thư viện',
                            trailing: _items.isEmpty ? null : 'Xem tất cả',
                            onTrailing: _items.isEmpty ? null : () => _open(const LibraryScreen()),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _Tile(
                                  key: const Key('tile-library'),
                                  icon: Icons.folder_outlined,
                                  label: 'Cuộc họp đã lưu',
                                  meta: '${_count(ItemKind.meeting) + _count(ItemKind.dialogue)} mục',
                                  onTap: () => _open(const LibraryScreen()),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _Tile(
                                  key: const Key('tile-upload'),
                                  icon: Icons.graphic_eq_rounded,
                                  label: 'Tải âm thanh lên',
                                  meta: _count(ItemKind.upload) == 0
                                      ? 'Từ tệp ghi âm'
                                      : '${_count(ItemKind.upload)} tệp',
                                  onTap: () => _open(const UploadScreen()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          _SectionLabel('Sắp tới'),
                          const SizedBox(height: 10),
                          if (!_calendarOn)
                            _ConnectCalendar(onTap: _askCalendar)
                          else if (_events.isEmpty)
                            const _Hint('Không có cuộc họp nào trong hai tuần tới.')
                          else
                            for (final e in _events.take(4))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _EventCard(
                                  event: e,
                                  onStart: () => _open(MeetingSetupScreen(suggestedTitle: e.title)),
                                ),
                              ),
                        ],
                      ),
              ),
              _StartDock(onMeeting: () => _open(const MeetingSetupScreen())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 8, 14),
    child: Row(
      children: [
        DecoratedBox(
          decoration: const ShapeDecoration(color: C.surface, shape: StadiumBorder()),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: FittedBox(fit: BoxFit.scaleDown, child: ScoaiLogo()),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Cài đặt',
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          onPressed: () => _open(const SettingsScreen()),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing, this.onTrailing});
  final String text;
  final String? trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: C.ink),
      ),
      const Spacer(),
      if (trailing != null)
        GestureDetector(
          onTap: onTrailing,
          child: Text(
            trailing!,
            style: const TextStyle(fontSize: 14, color: C.brand, fontWeight: FontWeight.w600),
          ),
        ),
    ],
  );
}

/// The most recent saved meeting, as home's first card.
class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.item, required this.onTap});
  final LibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final overview = item.summary?.overview.trim() ?? '';
    final subtitle = overview.isNotEmpty
        ? overview
        : item.sentences.isEmpty
        ? 'Chưa có nội dung.'
        : (item.sentences.first.hasTranslation ? item.sentences.first.translation : item.sentences.first.source);
    return Material(
      key: const Key('latest-card'),
      color: C.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      shadowColor: C.ink.withValues(alpha: 0.18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: C.accent),
                  const SizedBox(width: 6),
                  Text(
                    item.summary == null ? 'Gần đây nhất' : 'Tóm tắt gần nhất',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: C.inkMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, height: 26 / 19, fontWeight: FontWeight.w700, color: C.ink),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 21 / 14, color: C.inkMuted),
              ),
              const SizedBox(height: 10),
              Text(
                '${dayLabel(item.createdAt)} · ${minutesLabel(item.duration)}',
                style: const TextStyle(fontSize: 12, color: C.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('empty-card'),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: C.surface,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: C.ink.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6))],
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chưa có cuộc họp nào',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.ink),
        ),
        SizedBox(height: 6),
        Text(
          'Bấm Bắt đầu cuộc họp. Người khác nói tiếng Trung hay tiếng Anh đều được, app dịch sang tiếng Việt ngay trên màn hình.',
          style: TextStyle(fontSize: 14, height: 21 / 14, color: C.inkMuted),
        ),
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.label, required this.meta, required this.onTap});
  final IconData icon;
  final String label;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: C.surface,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 104,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: C.brand),
            const Spacer(),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink),
            ),
            const SizedBox(height: 2),
            Text(meta, style: const TextStyle(fontSize: 12, color: C.inkMuted)),
          ],
        ),
      ),
    ),
  );
}

class _ConnectCalendar extends StatelessWidget {
  const _ConnectCalendar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('connect-calendar'),
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: C.brandSoft, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.calendar_month_outlined, size: 20, color: C.brand),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nối lịch điện thoại',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Thấy cuộc họp sắp tới và bắt đầu ghi bằng một chạm.',
                    style: TextStyle(fontSize: 13, color: C.inkMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: C.inkMuted),
          ],
        ),
      ),
    ),
  );
}

/// One upcoming meeting: a left bar, its time, and a mic that starts a
/// meeting already named after it.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onStart});
  final UpcomingEvent event;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: C.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: C.hairline),
    ),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 44,
          margin: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink),
                ),
                const SizedBox(height: 2),
                Text(eventWhen(event), style: const TextStyle(fontSize: 13, color: C.inkMuted)),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Bắt đầu ghi cuộc họp này',
          icon: const Icon(Icons.mic_none_rounded, color: C.accent),
          onPressed: onStart,
        ),
      ],
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(text, style: const TextStyle(fontSize: 14, color: C.inkMuted)),
  );
}

class _StartDock extends StatelessWidget {
  const _StartDock({required this.onMeeting});
  final VoidCallback onMeeting;

  @override
  Widget build(BuildContext context) => Container(
    color: C.paper,
    padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.paddingOf(context).bottom),
    child: AccentButton(
      key: const Key('start-meeting'),
      label: 'Bắt đầu cuộc họp',
      icon: Icons.mic_none_rounded,
      height: 58,
      onPressed: onMeeting,
    ),
  );
}

/// "Hôm nay", "Hôm qua" or "12/11".
String dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  if (d == today) return 'Hôm nay';
  if (d == today.subtract(const Duration(days: 1))) return 'Hôm qua';
  return '${_two(t.day)}/${_two(t.month)}';
}

String minutesLabel(Duration d) => d.inMinutes < 1 ? '${d.inSeconds} giây' : '${d.inMinutes} phút';

/// "Hôm nay · 15:30" for an upcoming meeting.
String eventWhen(UpcomingEvent e) {
  final day = dayLabel(e.start);
  if (e.allDay) return '$day · cả ngày';
  return '$day · ${_two(e.start.hour)}:${_two(e.start.minute)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

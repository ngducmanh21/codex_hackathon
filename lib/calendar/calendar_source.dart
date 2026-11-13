import 'package:device_calendar/device_calendar.dart';

/// A meeting coming up in the phone's calendar ("Sắp tới").
class UpcomingEvent {
  const UpcomingEvent({required this.title, required this.start, this.end, this.location, this.allDay = false});
  final String title;
  final DateTime start;
  final DateTime? end;
  final String? location;
  final bool allDay;
}

/// Reads upcoming meetings, read-only.
abstract class CalendarSource {
  Future<bool> hasPermission();
  Future<bool> requestPermission();

  /// Events starting from now (or still running) within [within], soonest
  /// first.
  Future<List<UpcomingEvent>> upcoming({Duration within = const Duration(days: 14), int limit = 20});
}

/// The phone's calendars through `device_calendar` (Android CalendarContract).
class DeviceCalendarSource implements CalendarSource {
  final _plugin = DeviceCalendarPlugin();

  @override
  Future<bool> hasPermission() async => (await _plugin.hasPermissions()).data ?? false;

  @override
  Future<bool> requestPermission() async => (await _plugin.requestPermissions()).data ?? false;

  @override
  Future<List<UpcomingEvent>> upcoming({Duration within = const Duration(days: 14), int limit = 20}) async {
    if (!await hasPermission()) return const [];
    final now = DateTime.now();
    final calendars = (await _plugin.retrieveCalendars()).data ?? const <Calendar>[];
    final out = <UpcomingEvent>[];
    for (final cal in calendars) {
      final id = cal.id;
      if (id == null) continue;
      final events = (await _plugin.retrieveEvents(
            id,
            RetrieveEventsParams(startDate: now.subtract(const Duration(hours: 1)), endDate: now.add(within)),
          ))
              .data ??
          const <Event>[];
      for (final e in events) {
        final start = e.start;
        final title = (e.title ?? '').trim();
        if (start == null || title.isEmpty) continue;
        final end = e.end;
        // Keep events still running; drop those already over.
        if ((end ?? start).isBefore(now)) continue;
        out.add(UpcomingEvent(
          title: title,
          start: start.toLocal(),
          end: end?.toLocal(),
          location: e.location,
          allDay: e.allDay ?? false,
        ));
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out.take(limit).toList();
  }
}

/// Sample meetings for "Chế độ thử".
class DemoCalendarSource implements CalendarSource {
  DemoCalendarSource({DateTime Function()? clock}) : _now = clock ?? DateTime.now;
  final DateTime Function() _now;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<List<UpcomingEvent>> upcoming({Duration within = const Duration(days: 14), int limit = 20}) async {
    final n = _now();
    final today = DateTime(n.year, n.month, n.day);
    DateTime at(int days, int hour, [int minute = 0]) => today.add(Duration(days: days, hours: hour, minutes: minute));
    final soon = DateTime(n.year, n.month, n.day, n.hour).add(const Duration(hours: 1));
    return [
      UpcomingEvent(title: 'Họp nhà cung cấp Thâm Quyến', start: soon, end: soon.add(const Duration(hours: 1)), location: 'Zoom'),
      UpcomingEvent(title: 'Chào hàng khách Mỹ', start: at(1, 9, 30), end: at(1, 10, 30)),
      UpcomingEvent(title: 'Kiểm tra mẫu với đối tác Quảng Châu', start: at(2, 14), end: at(2, 15)),
      UpcomingEvent(title: 'Họp nhóm tuần', start: at(4, 8, 30), end: at(4, 9, 30)),
    ].take(limit).toList();
  }
}

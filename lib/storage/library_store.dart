import 'dart:convert';
import 'dart:io';

import '../domain/records.dart';

/// Saved items as one JSON file each under [dir].
///
/// Writes go to a temporary file first and are renamed into place, so a
/// crash mid-write never leaves a half-written item.
class LibraryStore {
  LibraryStore(this.dir);

  final Directory dir;

  File _fileFor(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'unsafe item id');
    }
    return File('${dir.path}/$id.json');
  }

  Future<List<LibraryItem>> list() async {
    if (!await dir.exists()) return const [];
    final items = <LibraryItem>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(await e.readAsString()) as Map<String, Object?>;
        items.add(LibraryItem.fromJson(j));
      } on Object {
        // A corrupt file must not hide the rest of the library.
        continue;
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<LibraryItem?> get(String id) async {
    final f = _fileFor(id);
    if (!await f.exists()) return null;
    return LibraryItem.fromJson(
      jsonDecode(await f.readAsString()) as Map<String, Object?>,
    );
  }

  Future<void> save(LibraryItem item) async {
    await dir.create(recursive: true);
    final f = _fileFor(item.id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(item.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> delete(String id) async {
    final f = _fileFor(id);
    if (await f.exists()) await f.delete();
  }
}

/// A new id that sorts by time and is safe as a file name.
String newItemId([DateTime? now]) {
  final t = (now ?? DateTime.now()).toUtc();
  final stamp = t.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
  final rand = (t.microsecondsSinceEpoch % 0xFFFFF).toRadixString(36);
  return '$stamp-$rand';
}

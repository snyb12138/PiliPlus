import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/models/user/jm_reading_list.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_utils.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

abstract final class JmReadingListStore {
  static final revision = ValueNotifier(0);
  static const maxEntries = 5000; // JM Lite's per-file import limit.
  static const _storageKey = 'entriesV1';

  static List<JmReadingEntry> get entries {
    final raw = GStorage.jmReadingList.get(_storageKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => JmReadingEntry.fromJson(item as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  static Future<bool> add(Iterable<String> ids, JmCommentSource source) async {
    final next = JmReadingList.add(entries, ids, source);
    if (next.length > maxEntries) return false;
    await _save(next);
    return true;
  }

  static Future<void> remove(String id) =>
      _save(entries.where((entry) => entry.id != id));

  static Future<void> _save(Iterable<JmReadingEntry> entries) async {
    await GStorage.jmReadingList.put(
      _storageKey,
      jsonEncode([for (final entry in entries) entry.toJson()]),
    );
    revision.value++;
  }

  static Future<void> export() async {
    final snapshot = entries;
    if (snapshot.isEmpty) return;
    final now = DateTime.now();
    await StorageUtils.saveBytes2File(
      name:
          'jm-lite-reading-list-${now.toIso8601String().split('T').first}.json',
      bytes: Uint8List.fromList(
        utf8.encode(JmReadingList.encodeShare(snapshot, now)),
      ),
    );
  }
}

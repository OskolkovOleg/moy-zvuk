import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'library_store.dart';
import 'listening_stats.dart';
import 'personal_models.dart';

const _statsKey = 'listening-stats-v1';

Future<ListeningStats> _readStats(
  DatabaseExecutor txn,
  String account,
  DateTime now,
) async {
  final rows = await txn.query(
    'state',
    where: 'account=? AND key=?',
    whereArgs: [account, _statsKey],
  );
  final stats = ListeningStats.fromJson(
    rows.isEmpty ? null : jsonDecode(rows.single['value'] as String),
    now,
  );
  if (rows.isEmpty) {
    final history = await txn.query(
      'state',
      where: 'account=? AND key=?',
      whereArgs: [account, 'listening-history'],
    );
    if (history.isNotEmpty) {
      for (final row in (jsonDecode(
        history.single['value'] as String,
      ) as List).whereType<Map<String, dynamic>>()) {
        final entry = ListeningEntry.fromJson(row);
        _lastKnown(stats, entry.track.id, entry.at);
      }
    }
  }
  return stats;
}

void _lastKnown(ListeningStats stats, String id, DateTime at) {
  if (stats.last[id] == null || at.isAfter(stats.last[id]!)) {
    stats.last[id] = at;
  }
}

Future<void> _writeStats(
  DatabaseExecutor txn,
  String account,
  ListeningStats stats,
) => txn
    .insert('state', {
      'account': account,
      'key': _statsKey,
      'value': jsonEncode(stats.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace)
    .then((_) {});

class ListeningStatsStore {
  const ListeningStatsStore(this.store);
  final LibraryStore store;
  Future<ListeningStats> load(String account, {DateTime? now}) =>
      store.db.transaction((txn) async {
        final at = now ?? DateTime.now();
        final stats = await _readStats(txn, account, at);
        stats.starts.removeWhere(
          (e) => e.at.isBefore(at.subtract(const Duration(days: 8))),
        );
        await _writeStats(txn, account, stats);
        return stats;
      });
  Future<void> mergeDates(String account, List<ListeningEntry> entries) =>
      store.db.transaction((txn) async {
        final stats = await _readStats(txn, account, DateTime.now());
        for (final e in entries) {
          _lastKnown(stats, e.track.id, e.at);
        }
        await _writeStats(txn, account, stats);
      });
  // Called in the SAME transaction as local history, so no successful history
  // record can silently miss its frequency event.
  static Future<void> record(
    DatabaseExecutor txn,
    String account,
    String track,
    DateTime at, {
    String? eventId,
  }) async {
    final stats = await _readStats(txn, account, at);
    final id = eventId ?? const Uuid().v4();
    _lastKnown(stats, track, at);
    if (!stats.starts.any((e) => e.id == id)) {
      stats.starts.add(ListeningStart(id, track, at));
    }
    stats.starts.removeWhere(
      (e) => e.at.isBefore(at.subtract(const Duration(days: 8))),
    );
    await _writeStats(txn, account, stats);
  }
}

/// A retry/pause/resume uses the same occurrence; selecting another entry or
/// explicitly replaying a finished song starts a fresh one.
class ListeningOccurrence {
  int? _entry;
  String? _id;
  String idFor(int entry) {
    if (_entry != entry || _id == null) {
      _entry = entry;
      _id = const Uuid().v4();
    }
    return _id!;
  }

  void reset() {
    _entry = null;
    _id = null;
  }
}

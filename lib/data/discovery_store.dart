import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'library_store.dart';
import 'models.dart';
import 'discovery_models.dart';

class DiscoveryMemory {
  DiscoveryMemory({
    Map<String, DateTime>? offered,
    List<Track>? hidden,
    this.cycle = 0,
    Map<String, int>? cursors,
  }) : offered = offered ?? {},
       hidden = hidden ?? [],
       cursors = cursors ?? {};
  final Map<String, DateTime> offered;
  final List<Track> hidden;
  int cycle;
  final Map<String, int> cursors;
  Set<String> excluded(DateTime now) => {
    ...hidden.expand(discoveryIdentity),
    ...offered.entries
        .where((e) => e.value.isAfter(now.subtract(const Duration(days: 7))))
        .map((e) => e.key),
  };
  factory DiscoveryMemory.fromJson(dynamic json) {
    if (json is! Map) return DiscoveryMemory();
    final offers = <String, DateTime>{};
    if (json['offered'] case final Map values) {
      for (final entry in values.entries) {
        final date = DateTime.tryParse(entry.value.toString());
        if (date != null) offers[entry.key.toString()] = date;
      }
    }
    return DiscoveryMemory(
      offered: offers,
      cycle: json['cycle'] is int ? json['cycle'] as int : 0,
      cursors: json['cursors'] is Map
          ? {
              for (final e in (json['cursors'] as Map).entries)
                if (e.value is int && (e.value as int) >= 0)
                  e.key.toString(): e.value as int,
            }
          : {},
      hidden: (json['hidden'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((j) => j['id'] is String && j['title'] is String)
          .map(Track.fromJson)
          .toList(),
    );
  }
  Map<String, dynamic> toJson() => {
    'cycle': cycle,
    'cursors': cursors,
    'offered': offered.map(
      (key, value) => MapEntry(key, value.toUtc().toIso8601String()),
    ),
    'hidden': hidden.map((t) => t.toJson()).toList(),
  };
}

class DiscoveryStore {
  const DiscoveryStore(this.store);
  final LibraryStore store;
  static const _key = 'discovery-v1';
  Future<DiscoveryMemory> load(String account) async =>
      DiscoveryMemory.fromJson(await store.get(account, _key));

  Future<void> _change(String account, void Function(DiscoveryMemory) edit) =>
      store.db.transaction((txn) async {
        final rows = await txn.query(
          'state',
          where: 'account=? AND key=?',
          whereArgs: [account, _key],
        );
        final memory = DiscoveryMemory.fromJson(
          rows.isEmpty ? null : jsonDecode(rows.single['value'] as String),
        );
        edit(memory);
        await txn.insert('state', {
          'account': account,
          'key': _key,
          'value': jsonEncode(memory.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });

  Future<void> offered(
    String account,
    List<Track> tracks,
    DateTime now, {
    Map<String, int> cursors = const {},
  }) => _change(account, (m) {
    m.cycle++;
    m.cursors.addAll(cursors);
    m.offered.removeWhere(
      (_, at) => !at.isAfter(now.subtract(const Duration(days: 7))),
    );
    for (final track in tracks) {
      for (final key in discoveryIdentity(track)) {
        m.offered[key] = now;
      }
    }
    final entries = m.offered.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    m.offered
      ..clear()
      ..addEntries(entries.take(2000));
  });
  Future<void> hide(String account, Track track) => _change(account, (m) {
    m.hidden.removeWhere(
      (t) => discoveryIdentity(t).any(discoveryIdentity(track).contains),
    );
    m.hidden.add(track);
  });
  Future<void> restore(String account, Track track) => _change(account, (m) {
    final keys = discoveryIdentity(track);
    m.hidden.removeWhere((t) => discoveryIdentity(t).any(keys.contains));
    for (final key in keys) {
      m.offered.remove(key);
    }
  });
  Future<void> resetRecent(String account) => _change(account, (m) {
    m.offered.clear();
    m.cursors.clear();
  });
}

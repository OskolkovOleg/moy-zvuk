import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'library_store.dart';
import 'models.dart';
import 'personal_models.dart';

class HistoryStore {
  const HistoryStore(this.store);
  final LibraryStore store;
  Future<List<ListeningEntry>> recent(String account) async =>
      ((await store.get(account, 'listening-history')) as List? ?? [])
          .map((j) => ListeningEntry.fromJson(j))
          .toList();

  Future<void> record(String account, Track track, DateTime at) =>
      store.db.transaction((txn) async {
        final rows = await txn.query(
          'state',
          where: 'account=? AND key=?',
          whereArgs: [account, 'listening-history'],
        );
        final previous = rows.isEmpty
            ? <ListeningEntry>[]
            : (jsonDecode(rows.single['value'] as String) as List)
                  .map((j) => ListeningEntry.fromJson(j))
                  .toList();
        final entries = recentUnique([ListeningEntry(track, at), ...previous]);
        await txn.insert('state', {
          'account': account,
          'key': 'listening-history',
          'value': jsonEncode(entries.map((e) => e.toJson()).toList()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
}

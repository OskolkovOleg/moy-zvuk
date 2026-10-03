import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'library_store.dart';

String normalizeSearch(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

class SearchHistoryStore {
  const SearchHistoryStore(this.store);
  final LibraryStore store;
  static const _key = 'search-history';

  List<String> _decode(dynamic raw) {
    final seen = <String>{};
    return (raw is List ? raw : const [])
        .whereType<String>()
        .map(normalizeSearch)
        .where((s) => s.isNotEmpty && seen.add(s.toLowerCase()))
        .take(20)
        .toList();
  }

  Future<List<String>> recent(String account) async =>
      _decode(await store.get(account, _key));

  Future<void> _change(
    String account,
    List<String> Function(List<String>) edit,
  ) => store.db.transaction((txn) async {
    final rows = await txn.query(
      'state',
      where: 'account=? AND key=?',
      whereArgs: [account, _key],
    );
    final before = rows.isEmpty
        ? <String>[]
        : _decode(jsonDecode(rows.single['value'] as String));
    await txn.insert('state', {
      'account': account,
      'key': _key,
      'value': jsonEncode(_decode(edit(before))),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  Future<void> record(String account, String query) {
    final value = normalizeSearch(query);
    if (value.isEmpty) return Future.value();
    return _change(account, (before) => [value, ...before]);
  }

  Future<void> remove(String account, String query) => _change(
    account,
    (before) => before
        .where((s) => s.toLowerCase() != normalizeSearch(query).toLowerCase())
        .toList(),
  );
  Future<void> clear(String account) => _change(account, (_) => []);
}

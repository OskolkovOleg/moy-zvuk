import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'models.dart';

class LibraryStore {
  LibraryStore(this.db);
  final Database db;

  static Future<LibraryStore> open({
    DatabaseFactory? factory,
    String? databasePath,
  }) async {
    final f = factory ?? databaseFactory;
    final location =
        databasePath ??
        path.join(await f.getDatabasesPath(), 'zvuk_personal.db');
    final db = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE votes (account TEXT NOT NULL, id TEXT NOT NULL, track TEXT NOT NULL, delta INTEGER NOT NULL CHECK(delta IN (-1,1)), created TEXT NOT NULL, undone INTEGER NOT NULL DEFAULT 0 CHECK(undone IN (0,1)), metadata TEXT NOT NULL, PRIMARY KEY(account,id))',
          );
          await db.execute('CREATE INDEX votes_track ON votes(account,track)');
          await db.execute(
            'CREATE TABLE state (account TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(account,key))',
          );
          await _createDownloads(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _createDownloads(db);
        },
      ),
    );
    return LibraryStore(db);
  }

  static Future<void> _createDownloads(Database db) => db.execute(
    'CREATE TABLE downloads (account TEXT NOT NULL, track TEXT NOT NULL, metadata TEXT NOT NULL, file TEXT NOT NULL, state TEXT NOT NULL, bytes INTEGER NOT NULL, created TEXT NOT NULL, error TEXT, PRIMARY KEY(account,track))',
  );

  Future<String> vote(String account, Track track, int delta) async {
    if (delta != -1 && delta != 1) {
      throw ArgumentError('Оценка должна быть +1 или −1');
    }
    final id = const Uuid().v4();
    await db.insert('votes', {
      'account': account,
      'id': id,
      'track': track.id,
      'delta': delta,
      'created': DateTime.now().toUtc().toIso8601String(),
      'undone': 0,
      'metadata': jsonEncode(track.toJson()),
    });
    return id;
  }

  Future<void> undo(String account, String id) async {
    await db.update(
      'votes',
      {'undone': 1},
      where: 'account=? AND id=?',
      whereArgs: [account, id],
    );
  }

  Future<Map<String, Rating>> ratings(String account) async {
    final rows = await db.rawQuery(
      'SELECT track, SUM(delta) AS score, COUNT(*) AS count FROM votes WHERE account=? AND undone=0 GROUP BY track',
      [account],
    );
    return {
      for (final row in rows)
        row['track'] as String: Rating(
          initialTrackScore + (row['score'] as int),
          row['count'] as int,
        ),
    };
  }

  Future<void> put(String account, String key, dynamic value) async {
    await db.insert('state', {
      'account': account,
      'key': key,
      'value': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<dynamic> get(String account, String key) async {
    final rows = await db.query(
      'state',
      where: 'account=? AND key=?',
      whereArgs: [account, key],
    );
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }

  Future<void> saveTracks(String account, String list, List<Track> tracks) =>
      put(account, 'list:$list', tracks.map((t) => t.toJson()).toList());
  Future<List<Track>> loadTracks(String account, String list) async =>
      ((await get(account, 'list:$list')) as List? ?? [])
          .map((j) => Track.fromJson(j))
          .toList();

  Future<List<String>> loadOrder(String account, String list) async =>
      List<String>.from(await get(account, 'order:$list') as List? ?? []);

  Future<void> saveOrder(String account, String list, List<String> order) =>
      put(account, 'order:$list', order);

  Future<String> exportRatings(String account) async {
    final rows = await db.query(
      'votes',
      where: 'account=?',
      whereArgs: [account],
      orderBy: 'created,id',
    );
    final orders = await db.query(
      'state',
      where: 'account=? AND key LIKE ?',
      whereArgs: [account, 'order:%'],
    );
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'account': account,
      'orders': {
        for (final row in orders)
          (row['key'] as String).substring(6): jsonDecode(
            row['value'] as String,
          ),
      },
      'events': rows
          .map(
            (r) => {
              'id': r['id'],
              'track': r['track'],
              'delta': r['delta'],
              'created': r['created'],
              'undone': r['undone'] == 1,
              'metadata': jsonDecode(r['metadata'] as String),
            },
          )
          .toList(),
    });
  }

  Future<int> importRatings(String account, String source) async {
    if (source.length > 20 * 1024 * 1024) {
      throw const FormatException('Файл слишком большой');
    }
    final dynamic raw;
    try {
      raw = jsonDecode(source);
    } catch (_) {
      throw const FormatException('Не удалось прочитать JSON');
    }
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['account'] != account ||
        raw['events'] is! List) {
      throw const FormatException(
        'Нужна резервная копия версии 1 для этого аккаунта',
      );
    }
    final events = <Map<String, Object?>>[];
    final orders = raw['orders'] ?? <String, dynamic>{};
    if (orders is! Map ||
        orders.entries.any(
          (e) =>
              e.key is! String ||
              (e.key as String).isEmpty ||
              e.value is! List ||
              (e.value as List).any((id) => id is! String || id.isEmpty),
        )) {
      throw const FormatException('В копии повреждён порядок треков');
    }
    for (final e in raw['events']) {
      if (e is! Map ||
          e['id'] is! String ||
          (e['id'] as String).isEmpty ||
          e['track'] is! String ||
          (e['track'] as String).isEmpty ||
          e['delta'] is! int ||
          ![-1, 1].contains(e['delta']) ||
          e['created'] is! String ||
          DateTime.tryParse(e['created']) == null ||
          e['undone'] is! bool ||
          e['metadata'] is! Map<String, dynamic>) {
        throw const FormatException('В копии есть повреждённая оценка');
      }
      final Track track;
      try {
        track = Track.fromJson(e['metadata']);
      } catch (_) {
        throw const FormatException('В копии повреждено описание трека');
      }
      if (track.id != e['track']) {
        throw const FormatException('ID трека не совпадает');
      }
      events.add({
        'account': account,
        'id': e['id'],
        'track': track.id,
        'delta': e['delta'],
        'created': e['created'],
        'undone': e['undone'] ? 1 : 0,
        'metadata': jsonEncode(track.toJson()),
      });
    }
    return db.transaction((txn) async {
      var added = 0;
      for (final event in events) {
        final existing = await txn.query(
          'votes',
          where: 'account=? AND id=?',
          whereArgs: [account, event['id']],
        );
        if (existing.isEmpty) {
          await txn.insert('votes', event);
          added++;
        } else {
          final old = existing.first;
          if (['track', 'delta', 'created'].any((k) => old[k] != event[k])) {
            throw const FormatException('Копия содержит конфликтующие оценки');
          }
          // Cancellation wins so importing an older backup cannot revive a vote.
          if (event['undone'] == 1) {
            await txn.update(
              'votes',
              {'undone': 1},
              where: 'account=? AND id=?',
              whereArgs: [account, event['id']],
            );
          }
        }
      }
      // Existing local arrangements win; a backup fills lists not arranged here.
      for (final entry in orders.entries) {
        await txn.insert('state', {
          'account': account,
          'key': 'order:${entry.key}',
          'value': jsonEncode(entry.value),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      return added;
    });
  }

  Future<void> close() => db.close();
}

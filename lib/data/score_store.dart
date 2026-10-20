part of 'library_store.dart';

Future<void> _createScoreData(
  DatabaseExecutor db, {
  bool legacy = false,
}) async {
  await db.execute(
    'CREATE TABLE score_bases (account TEXT NOT NULL, track TEXT NOT NULL, base INTEGER NOT NULL CHECK(base IN (9,10)), PRIMARY KEY(account,track))',
  );
  if (!legacy) return;
  await db.execute(
    'INSERT INTO score_bases(account,track,base) SELECT DISTINCT account,track,10 FROM votes',
  );
  final lists = await db.query(
    'state',
    where: 'key=?',
    whereArgs: ['list:favorites'],
  );
  for (final row in lists) {
    dynamic value;
    try {
      value = jsonDecode(row['value'] as String);
    } on FormatException {
      continue;
    }
    if (value is! List) continue;
    for (final track in value.whereType<Map>()) {
      if (track['id'] is! String || (track['id'] as String).isEmpty) continue;
      await db.insert('score_bases', {
        'account': row['account'],
        'track': track['id'],
        'base': 10,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}

Future<List<Track>> _storedTracks(
  DatabaseExecutor db,
  String account,
  String key,
) async {
  final rows = await db.query(
    'state',
    where: 'account=? AND key=?',
    whereArgs: [account, key],
  );
  if (rows.isEmpty) return [];
  return (jsonDecode(rows.single['value'] as String) as List)
      .map((value) => Track.fromJson(value as Map<String, dynamic>))
      .toList();
}

Future<void> _writeTracks(
  DatabaseExecutor db,
  String account,
  String key,
  List<Track> tracks,
) => db
    .insert('state', {
      'account': account,
      'key': key,
      'value': jsonEncode(tracks.map((t) => t.toJson()).toList()),
    }, conflictAlgorithm: ConflictAlgorithm.replace)
    .then((_) {});

Future<void> _collectTrack(
  DatabaseExecutor db,
  String account,
  Track track,
) async {
  final favorites = await _storedTracks(db, account, 'list:favorites');
  if (favorites.any((t) => t.id == track.id)) return;
  await _writeTracks(db, account, 'list:favorites', [track, ...favorites]);
  final pending = await _storedTracks(db, account, 'pending-favorite-adds');
  if (!pending.any((t) => t.id == track.id)) {
    await _writeTracks(db, account, 'pending-favorite-adds', [
      ...pending,
      track,
    ]);
  }
}

extension ScoreLibraryStore on LibraryStore {
  Future<List<Track>> pendingFavoriteAdds(String account) =>
      _storedTracks(db, account, 'pending-favorite-adds');

  Future<void> completeFavoriteAdd(String account, String trackId) =>
      db.transaction((txn) async {
        final pending = await _storedTracks(
          txn,
          account,
          'pending-favorite-adds',
        );
        await _writeTracks(
          txn,
          account,
          'pending-favorite-adds',
          pending.where((t) => t.id != trackId).toList(),
        );
      });

  Future<List<Track>> mergeFavorites(String account, List<Track> remote) =>
      db.transaction((txn) async {
        final pending = await _storedTracks(
          txn,
          account,
          'pending-favorite-adds',
        );
        final remoteIds = remote.map((t) => t.id).toSet();
        final merged = [
          ...pending.where((t) => !remoteIds.contains(t.id)),
          ...remote,
        ];
        await _writeTracks(txn, account, 'list:favorites', merged);
        return merged;
      });
}

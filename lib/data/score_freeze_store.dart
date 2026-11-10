part of 'library_store.dart';

const _scoreFreezePrefix = 'score-frozen:';

class ScoreFrozenException implements Exception {
  const ScoreFrozenException();
  @override
  String toString() => 'Балл зафиксирован. Удержи цифру, чтобы снять фиксацию.';
}

Future<bool> _scoreFrozen(
  DatabaseExecutor db,
  String account,
  String track,
) async => (await db.query(
  'state',
  columns: ['key'],
  where: 'account=? AND key=? AND value=?',
  whereArgs: [account, '$_scoreFreezePrefix$track', 'true'],
)).isNotEmpty;

Future<Set<String>> _frozenScores(DatabaseExecutor db, String account) async {
  final rows = await db.query(
    'state',
    columns: ['key'],
    where: 'account=? AND key LIKE ? AND value=?',
    whereArgs: [account, '$_scoreFreezePrefix%', 'true'],
  );
  return {
    for (final row in rows)
      (row['key'] as String).substring(_scoreFreezePrefix.length),
  };
}

extension ScoreFreezeStore on LibraryStore {
  /// Serializes the flag with votes so a stale notification cannot change a
  /// score after it has been frozen. Existing scores and collection stay intact.
  Future<bool> toggleScoreFreeze(String account, String track) =>
      db.transaction((txn) async {
        final frozen = await _scoreFrozen(txn, account, track);
        if (frozen) {
          await txn.delete(
            'state',
            where: 'account=? AND key=?',
            whereArgs: [account, '$_scoreFreezePrefix$track'],
          );
        } else {
          await txn.insert('state', {
            'account': account,
            'key': '$_scoreFreezePrefix$track',
            'value': 'true',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return !frozen;
      });
}

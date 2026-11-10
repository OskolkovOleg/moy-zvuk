part of 'app_controller.dart';

extension ScoreFreezeController on AppController {
  Future<T> _scoreEdit<T>(Future<T> Function(String account) edit) {
    final id = account?.id;
    final result = _scoreEdits.catchError((_) {}).then((_) async {
      if (_disposed || id == null || account?.id != id) {
        throw StateError('Аккаунт изменился. Повтори действие.');
      }
      return edit(id);
    });
    _scoreEdits = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _toggleScoreFreeze(Track track) => _scoreEdit((id) async {
    ++_ratingRevision;
    await store.toggleScoreFreeze(id, track.id);
    final updated = await store.ratings(id);
    if (_disposed || account?.id != id) return;
    ratings = updated;
    music.setNotificationRatings(id, ratings);
    notifyListeners();
  });
}

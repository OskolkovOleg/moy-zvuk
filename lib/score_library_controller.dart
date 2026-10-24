part of 'app_controller.dart';

extension ScoreLibraryController on AppController {
  Future<void> syncLibraryAdds() async {
    final session = api, id = account?.id;
    if (session == null || id == null || _disposed) return;
    try {
      await _edit((activeApi, accountId) async {
        final pending = await store.pendingFavoriteAdds(accountId);
        if (pending.isEmpty) return;
        final remoteIds = (await activeApi.favoriteIds()).toSet();
        for (final track in pending) {
          if (_disposed || api != activeApi || account?.id != accountId) return;
          // A previous write may have succeeded before its response was lost.
          if (!remoteIds.contains(track.id)) {
            await activeApi.setCollectionItem(track.id, liked: true);
            remoteIds.add(track.id);
          }
          await store.completeFavoriteAdd(accountId, track.id);
        }
      });
    } catch (_) {
      // The vote and library membership already committed locally. Keep the
      // pending addition for the next vote, reconnect or library refresh.
    }
  }
}

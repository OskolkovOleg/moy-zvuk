part of 'app_controller.dart';

extension PersonalCollection on AppController {
  bool hasCatalogItem(CatalogItem item) => savedCatalogItems.any(
    (saved) => saved.id == item.id && saved.kind == item.kind,
  );

  Future<void> refreshSavedCatalog() async {
    final session = api, id = account?.id;
    if (session == null || id == null || serverBusy) return;
    final request = ++_savedRequest, revision = _catalogRevision;
    savedCatalogLoading = true;
    savedCatalogError = null;
    _notifySavedCatalog();
    try {
      final items = await session.savedCatalog();
      if (api != session ||
          account?.id != id ||
          request != _savedRequest ||
          revision != _catalogRevision) {
        return;
      }
      // Update synchronously before the cache write; a newer edit must win.
      savedCatalogItems = items;
      savedCatalogKnown = true;
      await store.put(
        id,
        'saved-catalog',
        items.map((i) => i.toJson()).toList(),
      );
    } catch (e) {
      if (api == session && request == _savedRequest) {
        savedCatalogError = e is ZvukException
            ? e.message
            : 'Не удалось обновить коллекцию.';
      }
    } finally {
      if (request == _savedRequest) {
        savedCatalogLoading = false;
        _notifySavedCatalog();
      }
    }
  }

  Future<void> saveCatalogItem(CatalogItem item, bool liked) => _edit((
    session,
    id,
  ) async {
    if (item.kind != CatalogKind.album && item.kind != CatalogKind.artist) {
      throw ArgumentError('Only albums and artists belong to saved catalog');
    }
    ++_savedRequest;
    savedCatalogLoading = false;
    await session.setCollectionItem(item.id, liked: liked, kind: item.kind);
    if (api != session || account?.id != id) return;
    savedCatalogItems = savedCatalogItems
        .where((saved) => saved.id != item.id || saved.kind != item.kind)
        .toList();
    if (liked) savedCatalogItems.insert(0, item);
    savedCatalogError = null;
    await _readBack(session, () async {
      await store.put(
        id,
        'saved-catalog',
        savedCatalogItems.map((i) => i.toJson()).toList(),
      );
    });
  });
}

# Personal client implementation plan

> **For agentic workers:** Execute inline, task-by-task; no delegation requested. Use the existing execution workflow with checkpoints.

**Goal:** Add saved artists/albums, listening history and lyrics to the Android client.
**Architecture:** Small personal API extension; account-scoped controller and storage; three screens reuse the existing catalog/player components.
**Tech Stack:** Flutter 3.47.6, Dart 3.13.5, existing http/sqflite/just_audio.
**Spec:** docs/superpowers/specs/2026-10-03-personal-client-design.md

## Global constraints

Version 1.5.0+8; no new packages or DB migration; preserve points, order, queue and login. Physical device updates only signed `adb install --no-streaming -r`; tests only on emulator. Never put credentials or private listening data in Git/APK/logs. No Telegram delivery.

### Task 1: API and models

Files: lib/data/personal_models.dart, personal_api.dart; modify catalog_models.dart, catalog_api.dart, zvuk_api.dart; test/personal_api_test.dart, lyrics_test.dart.
Interfaces: savedCatalog() -> List<CatalogItem>; listeningHistory(offset:0,limit:50) -> HistoryPage; lyrics(trackId) -> SongLyrics?; setCollectionItem accepts CatalogKind (release enum for albums).
- [ ] Add fixtures for missing/null API rows, exact mutation enum and offset counting raw history rows (including episodes).
- [ ] Implement metadata batches preserving collection order, only artist/album kinds; serialize CatalogItem for cache.
- [ ] Implement lyrics parsing and active-line search, validate repeated tags, milliseconds, offset, plain/empty text with synthetic test lyrics.

```dart
expect(SongLyrics.parse('[00:01.25][00:02.5]Example').lines.map((l) => l.at?.inMilliseconds), [1250, 2500]);
```

### Task 2: Account state and history

Files: lib/personal_controller.dart, app_controller.dart, data/history_store.dart, playback/music_handler.dart; tests personal_controller_test.dart and history_store_test.dart.
Interfaces: refreshSavedCatalog(), saveCatalogItem(item, liked), hasCatalogItem(item); HistoryStore(store).record(account,track,date), recent(account).
- [ ] Use existing serialized _edit for album/artist likes; revision guard for concurrent reads, cache account scope and known-state flag.
- [ ] Record playback only in ready+playing state after a loaded source; one record per source, reset when source changes. Capture account/track synchronously before async transaction.
- [ ] Test racing refresh/mutation and changed API/account, concurrent history writes and 200-entry bound.

```dart
await Future.wait([history.record('a', first, now), history.record('a', second, now)]);
expect((await history.recent('a')).length, 2);
expect(await history.recent('b'), isEmpty);
```

### Task 3: UI

Files: lib/ui/saved_catalog_screen.dart, history_screen.dart, lyrics_screen.dart; modify library_screen.dart, catalog_detail_screen.dart, track_actions.dart, player_sheet.dart.
- [ ] Add compact section links; preserve score rows and reuse CatalogTile and PlayerScaffold.
- [ ] Album/artist save control disabled while state is unknown; retry exposed on errors, cache usable offline.
- [ ] History local/server filters, pagination and retry without discarding existing entries; taps play loaded list from selected index.
- [ ] Lyrics independent loading/empty/failure, plain or timed lines, translation toggle, active-line highlight and seek only for same current song.
- [ ] Emulator fixture UI verifies all new flows and captures synthetic screenshots at 360dp and 1.6x text scale.

### Task 4: Release

Files: pubspec.yaml, settings_screen.dart, README.md, docs/verification.md, test integration entry points.
- [ ] Read-only live API test and core suite, playback regression, formatter and analyzer.
- [ ] Build release, verify drawables/signature/secrets; mirror changed code preserving private docs; commit/push and wait for CI.
- [ ] Publish v1.5.0 release with APK; install over connected phone and cold-start; report exact result.

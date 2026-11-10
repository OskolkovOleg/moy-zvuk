# Newest library sort implementation plan

> Execute inline in the current session; the user requested implementation.

**Goal:** Add «Сначала новые» for songs most recently added to «Мои песни».

**Architecture:** Request Zvuk collection tracks with explicit `dateAdded` / `desc` ordering. Preserve that sequence in the account cache; sort the filtered list using that sequence. Record that the cached order is known only after a successful ordered server read.

**Tech Stack:** Flutter 3.47.6, Dart 3.13.5, SQLite, Zvuk GraphQL.

**Spec:** User request in this conversation; read-only API audit confirmed `dateAdded` descending and ascending are exact reversals for the collection. Metadata hydration preserves ID order. No title, ID or listening-date inference.

## Constraints

- Only «Мои песни» supports this option: playlist order does not prove addition order.
- Existing filters, frozen scores, stable rows and queue snapshots remain supported.
- Unknown legacy cache order requires an online refresh; a confirmed cache works offline.
- No changes to live playback or scores during verification.

## Task 1: API, order and persistence

Files: `lib/data/zvuk_api.dart`, `lib/data/listening_stats.dart`, `lib/data/score_store.dart`.

- [ ] Assert the API query contains `tracks(orderBy: dateAdded, orderDirection: desc)` and hydration preserves duplicate-free order.
- [ ] Preserve source order before score ranking:

```dart
if (sort == LibrarySort.newest) return List.of(tracks);
```

- [ ] Merge unsynced additions newest first, then server order:

```dart
...pending.reversed.where((t) => !remoteIds.contains(t.id)),
...remote,
```

- [ ] Persist account-specific `favorites-newest-first-v1: true` in the same transaction. Test reopening SQLite, account isolation and repeated votes without moving additions.

## Task 2: Controller and menu

Files: `lib/library_listening_controller.dart`, `lib/app_controller.dart`, `lib/ui/library_sort_control.dart`, `lib/ui/library_screen.dart`.

- [ ] Add `LibrarySort.newest` / «Сначала новые»; only history modes request listening stats.
- [ ] Before selecting newest, read the provenance marker; if unknown refresh, then reread. Guard asynchronous work by account, list, selection revision and sort request. Keep the previous sort with an explanatory message when unavailable.
- [ ] Add menu icon and subtitle «Последние добавленные в „Мои песни“»; hide for playlists.
- [ ] Test offline known/unknown order, filters and playback snapshot; capture 360 dp and 320 dp with 1.6× text.

## Task 3: Verify and deliver

- [ ] Bump to 1.19.2+33; format, analyze and run all tests in Ubuntu CI.
- [ ] Inspect screenshots; build ARM64 release in CI; sign with existing local certificate and verify payload.
- [ ] Install directly if phone is connected; record the actual installation result.
- [ ] Update verification docs and private mirror while preserving its history; commit app paths only.

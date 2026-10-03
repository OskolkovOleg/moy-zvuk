# Offline Audio Implementation Plan

**Execution:** Inline in the current authorized task; no additional agents or approval ceremony.
**Goal:** Download selected songs/lists and play them without network access.
**Architecture:** Account-scoped SQLite manifest, streaming atomic file writer and local-first MusicHandler. Dedicated downloads UI uses existing compact rows, scores and shuffle sheet.
**Tech Stack:** Flutter 3.47.6, Dart 3.13.5, sqflite, http, just_audio, vendored audio_service; no new plugins.
**Spec:** ../specs/2026-10-03-offline-audio-design.md

## Global constraints

- Android API 24 minimum; target 36; preserve signed update compatibility.
- Tokens and stream URLs never enter logs, manifest, repository or release.
- Preserve account, votes, manual order and queue. Negative scores never delete tracks.
- Compact library rows; full player without scrolling; ratings without success snackbar.
- Only explicit downloads over the current network. Interrupted work is retryable.
- No destructive actions or integration tests on the physical phone.

## Task 1: Durable downloader

Files: lib/data/library_store.dart; new lib/downloads/download_record.dart and download_manager.dart; test/download_manager_test.dart.
Interfaces: `DownloadManager(LibraryStore store, {http.Client Function()? clientFactory, Directory? directory})`; `Future<void> configure(String account, ZvukApi? api)`; `Future<void> enqueue(List<Track> tracks)`; `Future<void> cancel(String id)`; `Future<void> remove(String id)`; `Future<void> clear()`; `Future<String?> localPath(String account, String id)`; `Future<void> close()`; account-scoped `List<DownloadRecord> items` and ChangeNotifier progress.

- [ ] Write executable tests using MockClient and temporary SQLite/audio directories. Expected valid fixture is RIFF/WAVE; invalid HTML, truncated Content-Length and oversized payload must leave no completed file.
- [ ] Add schema 2 migration: `CREATE TABLE downloads (account TEXT NOT NULL, track TEXT NOT NULL, metadata TEXT NOT NULL, file TEXT NOT NULL, state TEXT NOT NULL, bytes INTEGER NOT NULL, created TEXT NOT NULL, error TEXT, PRIMARY KEY(account,track))`.
- [ ] Implement immutable manifest rows; validated UUID-style basename; app-private root; per-account query and atomic publication.
- [ ] Implement sequential transfers with independent HTTP clients, cancellation, timeouts, size limits, progress, sanitized errors and interrupted/orphan cleanup.
- [ ] Run new tests in integration_test/core_test.dart on Android and check account/restart/migration cases.

## Task 2: Local playback

Files: lib/playback/music_handler.dart; integration_test/offline_playback_test.dart.
Consumes Task 1 interfaces; MusicHandler produces `downloads` for UI.

- [ ] Configure and close downloader with handler lifecycle.
- [ ] In serialized source loader capture account, call `downloads.localPath(account, track.id)`, guard generation, call `player.setFilePath(path, initialPosition: position)` when present; otherwise use current API path.
- [ ] Download two fixture files through local debug HTTP, close server and rebuild handler from same database; API-null playback must seek and naturally advance offline.
- [ ] Exercise pause/play/next through the media notification while app is backgrounded; verify no online source requests and no playback errors.

## Task 3: Downloads UI

Files: new lib/ui/download_widgets.dart, downloads_screen.dart; lib/ui/library_screen.dart, track_actions.dart, catalog_detail_screen.dart, widgets.dart; integration_test/downloads_ui_test.dart.
Consumes `music.downloads` and Task 1 state/actions.

- [ ] Add state-aware menu item and shared download-list button with count/progress.
- [ ] Add «Скачанное» first library shortcut, storage summary, transfer controls, confirmed clear, completed-only play/rating sort and ShuffleSheet with best-N selection.
- [ ] Use a small downloaded marker on artwork; no extra row height.
- [ ] Capture narrow/large-text empty/progress/ready/failure states; verify download/cancel/retry/remove/play and no layout exceptions.

## Task 4: Release and install

Files: pubspec.yaml; README.md; docs/verification.md; exact changed paths mirrored privately.

- [ ] Format/analyze, full Android core/regression and offline tests on API 30 and 36; real account read-only stream/download probe without credential logging.
- [ ] Build signed APK, verify icons/certificate and APK/source secret scan.
- [ ] Signed 1.9.0→new update test on emulator only, comparing existing votes/state and completed audio persistence.
- [ ] Commit, push, confirm Ubuntu CI, publish release with verified asset digest and mirror exact changes.
- [ ] If phone is present, signed `adb install --no-streaming -r`; preserve its data. Otherwise report that installation awaits USB.

## Task 5: Live notification score (user addition)

Files: lib/playback/notification_controls.dart and music_handler.dart; lib/app_controller.dart; vendored AudioService.java; android/app/src/main/res/layout/zvuk_notification_rating.xml; res/raw/keep.xml; tool/verify_apk.py; debug TestActivity.kt; notification_rating_test.dart.
- [ ] Retain current account ratings in handler; update after app votes/undo and initial configure.
- [ ] Publish `zvukRatingScore` extras on existing minus/plus actions; update current MediaItem artist metadata when scores change.
- [ ] Decorated custom notification on API <33 contains minus/score/plus; include three transport controls in that view. Android 13+ keeps standard MediaSession layout and live subtitle score.
- [ ] Verify real RemoteViews clicks and MediaSession actions, immediate 10→11→12 score updates without playback disruption, account/track changes, stale actions, native resources and actual screenshots.

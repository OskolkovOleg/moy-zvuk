# Wave tuner and artist navigation implementation plan

> **For agentic workers:** Execute inline, task by task. No subagents requested.

**Goal:** Configure the personal wave and open artists directly from song names.
**Architecture:** Typed WaveOptions serialized into existing per-account state; MusicHandler invalidates future recommendations while preserving current audio. Shared artist navigator handles exact names and missing IDs.
**Tech Stack:** Existing Flutter 3.47.6/Dart 3.13.5, SQLite, just_audio and vendored audio_service.
**Spec:** docs/superpowers/specs/2026-10-03-wave-tuner-design.md

## Global constraints

Version 1.9.0+14; no new dependencies or schema migration. Preserve login, ratings, order, compact rows, no-scroll player and notification controls. Emulator-only tests. Signed physical update only; no uninstall/Telegram. No credentials in public source/APK.

## 1. Options and API

Files: lib/data/wave_options.dart, catalog_api.dart, radio_api.dart, zvuk_api.dart; test/wave_options_test.dart and integration_test/core_test.dart.
- [x] Define immutable `WaveOptions` with enum mood/language/popularity and validated genre list, JSON defaults, API options and Russian summary.
- [x] Add `personalWave({count,waveInput,WaveOptions options})`; `recommendations(...,WaveOptions options)` passes options only for personal source.
- [x] Verify null default variables, exact confirmed values, invalid cached values and contextual sources unchanged.

```dart
expect(const WaveOptions(mood: WaveMood.energetic).toApi()['mood'], 'energy:1,fun:0.5');
expect(WaveOptions.fromJson({'mood':'unknown'}).isDefault, true);
```

## 2. Playback preferences

Files: lib/playback/wave_preferences.dart, music_handler.dart; integration_test/wave_options_playback_test.dart.
- [x] Handler owns `WaveOptions waveOptions`, restores `waveOptions` state per account, saves through `setWaveOptions(WaveOptions options)` before publishing selection.
- [x] For active personal flow only, invalidate generation/buffer, clear upcoming, refill and save queue without calling audio load/stop/pause. Snapshot options before fetch. Pending next retries; stale errors suppressed.
- [x] Local WAV tests prove current entry, position and stream count unchanged, natural next uses new options, paused state/restore, account isolation, stale buffered response and manual/context queues untouched.

```dart
final entry = music.playlist.entryKey(music.playlist.index);
await music.setWaveOptions(const WaveOptions(language: WaveLanguage.russian));
expect(music.playlist.entryKey(music.playlist.index), entry);
expect(music.player.playing, true);
```

## 3. Interface and artist access

Files: lib/ui/wave_settings.dart, discover_screen.dart, artist_navigation.dart, widgets.dart, player_sheet.dart, player_content.dart, track_actions.dart; lib/data/models.dart; integration_test/wave_tuner_ui_test.dart.
- [x] Settings route with grouped chips, reset/cancel/save and inline errors; Discover summary rebuilds on music revision. Wrap controls at 320dp and 1.6× text.
- [x] Preserve `Track.artistNames` in API/cache; `openTrackArtist(context,app,track)` opens one or chooser, reads missing metadata, shows recoverable errors. Link `ArtistLink` in full player and compact rows; existing menu shares navigator.
- [x] UI test taps save/reset/cancel, checks persisted summary and opens collaboration artist by exact name; no playback restart and no layout overflow. Capture narrow/enlarged screenshots.

## 4. Deliver

- [x] Analyze/format/core, focused new UI/playback/live read-only probes and notification regression as needed.
- [x] Signed APK, eight resources/signature/secret checks and 1.8.2→1.9 update fixture; record actual evidence.
- [x] Commit/push/CI, release, mirror exact changed paths while preserving private docs. Phone install and cold launch if connected.

**Result:** 1.9.0 built and signed; UI, 69 Android checks, live reads, CI and signed update passed. Public release and mirror completed. Physical phone updated directly to 1.9.0; version and launch confirmed. See docs/verification.md.

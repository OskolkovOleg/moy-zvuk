# Playback controls implementation plan

> **For agentic workers:** Execute inline, task-by-task using the existing execution workflow. No delegation requested.

**Goal:** Make daily playback controllable with queue editing, repeat and sleep timer.
**Architecture:** Pure queue/timer state models; MusicHandler owns playback transitions; reusable controls and dedicated queue UI.
**Tech Stack:** Flutter 3.47.6 / Dart 3.13.5, existing just_audio, audio_service, SQLite.
**Spec:** docs/superpowers/specs/2026-10-03-playback-controls-design.md

## Global constraints

Version 1.6.0+9; preserve credentials, ratings, library order and queue; no package or SQLite schema changes. Tests on emulator only. Physical updates signed `adb install --no-streaming -r`, never uninstall. No Telegram. No credentials in public code, APK or logs.

### Task 1: Queue and timer state

Files: lib/playback/playback_queue.dart, sleep_timer.dart; test/playback_queue_test.dart, sleep_timer_test.dart.
Interfaces: entryKey(index), version, move(from,to), remove(index), clearUpcoming(), shuffleUpcoming(); SleepTimerState.schedule(duration,now), afterSong(), cancel(), expire(now), finishSong(), remaining(now).
- [ ] Tests for current occurrence identity across moves/removal, duplicates, empty/end boundaries and restore.
- [ ] Implement keys unique within queue instance and revision on index/content changes; cache serialization stays backward-compatible.
- [ ] Pure timer tests: exact deadline, replacement/cancellation, after-song mutually exclusive with timed mode.

```dart
final q = PlaybackQueue()..replace([a, b, a], 2);
final key = q.entryKey(2);
q.move(2, 0);
expect(q.entryKey(q.index), key);
q.remove(1);
expect(q.current, a);
```

### Task 2: Playback behavior

Files: lib/playback/music_handler.dart, playback_controls.dart; integration_test/playback_controls_test.dart.
Interfaces: MusicHandler.removeFromQueue(index,version), moveInQueue(from,to,version), moveNextInQueue(index,version), shuffleUpcoming(), clearUpcoming(), setRepeatMode(mode), setSleepTimer(duration), sleepAfterSong(), cancelSleepTimer(); nextTrack/upNextLabel for bounds-safe preview.
- [ ] Preserve current audio for non-current edits; stale versions return false. Current removal loads next only if previously playing; paused/empty cases do not start playback.
- [ ] Repeat natural completion and media commands, persist mode, clear when starting wave. Preview handles empty next wave batch.
- [ ] Timer state owned by handler, periodic deadline check cancels pending play through pause; end-song branch precedes repeat/wave.
- [ ] Local WAV tests for natural loop, manual next, paused removal, no interruption on reorder, timer in background and delayed load; wave clearing rejects late fetch.

```dart
await music.setRepeatMode(AudioServiceRepeatMode.one);
await music.playList([first, second], 0);
// Observe a second natural start of first, then explicit skip reaches second.
await music.skipToNext();
expect(music.playlist.current!.id, second.id);
```

### Task 3: Interface

Files: lib/ui/queue_view.dart, playback_controls.dart, player_sheet.dart; integration_test/playback_controls_ui_test.dart.
- [ ] Move queue UI out of player_sheet.dart; ReorderableListView keys use occurrence key, drag/drop snapshot version rejects stale edits.
- [ ] Per-row menu next/remove; toolbar shuffle remaining and clear remaining; labels explain local queue effect.
- [ ] Player repeat and sleep buttons, timer picker and countdown; safe next preview for repeat and empty wave continuation.
- [ ] Fixture UI interactions and screenshots at 360dp and 1.6x scale; no real private data in screenshots.

### Task 4: Release

Files: pubspec.yaml, settings_screen.dart, README.md, docs/verification.md; integration_test/core_test.dart.
- [ ] Core tests, new playback/UI integration and background regression; formatter and analyzer.
- [ ] Build 1.6.0 signed release; resource/signature/secret checks, upgrade fixture preserves data.
- [ ] Commit and push; CI passes; publish APK, mirror code and preserve private verification history.
- [ ] Install on physical phone only if it appears; otherwise report ready APK and USB limitation.

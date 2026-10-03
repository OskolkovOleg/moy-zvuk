# Personal wave tuner and artist navigation

Continue the existing client under the user's authorization to develop it with minimal questions. Architectural extension to stored playback preferences; execute inline. Add direct artist navigation requested during this work.

## Verified API

Read-only requests on 2026-10-03 confirmed `personalWaveContent(first, options: PersonalWaveOptions)` returns tracks for mood `energy:1,fun:1`, language `russian`, popularity `1`, genre `[{name:rock}]`, and situation `[workout]`. These fields also appear in the public Zvuk web player. Use mood, genre, language and popularity in this release; situations stay deferred. No server preference mutation or playback on the user's Chrome tab.

## Behavior

Discover retains its primary play action and gains a settings action and concise selection summary. Settings use grouped wrapping chips: neutral/energetic/happy/calm/sad mood, eleven established genre keys, all/Russian/foreign language, mixed/hits/discoveries popularity. Explicit save and reset; cancel discards edits. Persist per account in the existing SQLite state table.

Applying settings to an active personal wave preserves the current song, position, playing/paused state and history. Cancel stale recommendation requests, remove upcoming recommendations and refill using the new options. A pending next request retries under the new generation; old errors cannot pause current playback. Other wave sources and manual queues retain their existing behavior. Restore old preferences as defaults; corrupt preferences cannot discard the queue.

Artist names in the full player and song rows are visible links. One artist opens directly; collaborations offer a chooser. Share navigation with the existing song menu and resolve missing IDs from fresh track metadata. Preserve exact API artist names (including commas) for the chooser. Existing artist screen shows popular songs and albums and keeps playback running during navigation.

## Constraints and acceptance

Flutter/Dart and current dependencies unchanged. Version 1.9.0+14. Preserve token, ratings, manual order and existing queue data on signed update. Compact song rows and player without scroll remain. No rating toast. Keep five notification controls on Android 11/16. Tests only on emulators; physical install only with `adb install --no-streaming -r`, no uninstall or Telegram.

Verify typed options, API variables and filtering scope, persistence/account isolation, active playback continuity and stale request cancellation, artist single/multiple/missing metadata navigation, compact and enlarged-text UI. Read-only live filtered recommendations. Signed build, secret scan, upgrade fixture, CI, public release, mirror and direct installation if USB available.

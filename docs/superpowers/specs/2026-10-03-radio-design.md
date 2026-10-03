# Contextual music flows — 1.7.0 design

## Scope and authorization

Continue the user's existing personal client, with minimal questions and signed USB updates. This is an API/playback/UI extension. Execute inline; no delegation. The next release adds contextual recommendations; mood/language filters remain deferred until API verification.

## Confirmed API

Read-only probes of the account and the public Zvuk web client confirmed `recommenderRadio(onEntity:{id,type},first,cursor)` for TRACK, ARTIST and RELEASE. The cursor can repeat while returned songs change; equality does not mean exhaustion. PLAYLIST radio returned empty, while `personalWaveContent(first,waveInput:{waveType:PLAYLIST,waveId})` returned songs. FAVTRACKS also returned songs. Use those observed paths, and the existing personal endpoint for default flow.

## Behavior

A typed WaveSource stores personal/favorites/track/artist/album/playlist plus ID and display name. Starting a flow replaces the queue with recommendations and resets repeat; it is an explicit play action. Empty initial results leave the existing queue paused and show an error. Batches exclude the seed track and the last 200 queue songs, retry at most twice when repeated. New requests share the existing buffer and cancellation generations. A change of queue/account/pause during initial load rejects late results. Clearing upcoming disables any contextual flow.

Persist the source and radio cursor in optional queue fields; old queues restore exactly as before, paused. A malformed source disables further flow requests without discarding cached tracks or votes. Both initial and continuation requests use the original source. Manual skipping, repeat-one and sleep timer keep the established behavior. Do not claim infinite unique catalog content; a stalled flow offers retry.

The track menu adds two explicit actions: “Поток по песне” and “Добавить похожие в очередь”. The second reads one recommendation batch and appends up to 15 distinct songs to the end, excluding the selected track and songs already queued; it never starts/replaces playback. If the account or queue changed during loading, reject the insertion with a retry message. No server favorites/playlists are changed.

## UI

Reuse existing icons, sheet rows, outlined buttons and lime theme. Contextual play actions sit with play/shuffle on artist/album/playlist details. Discover groups the main personal flow and the favorites flow together. Keep compact library rows unchanged. A shared helper owns loading/error feedback and prevents repeat taps; a progress sheet may be dismissed without late playback starting. Check 360 dp and 1.6× text.

## Validation and release

Unit tests for API routing, source restore/validation, null entries and repeated cursors. Emulator tests for continuation on original seed, delayed cancellation, restore, non-interrupting queue insertion and UI actions. Live API reads only, token in memory through one-shot loopback bridge. Regress background playback and existing wave; build signed 1.7.0+10, verify notification resources/signature/secrets and upgrade fixture. Public GitHub release and private mirror. Install with `adb install --no-streaming -r` if phone is available; never uninstall or test on it; no Telegram.

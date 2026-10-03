# Offline audio

## Scope and choice

Implement explicit downloads for individual songs and complete loaded lists (favorites, playlists, albums). Automatic eviction-based streaming cache would not guarantee that a chosen song remains offline. A system background-transfer service would add a second native queue; this version uses a sequential streaming downloader in the existing app process. Downloads can continue while that process remains active; interrupted jobs remain visible and can be retried after reopening.

## Experience

Library has a first-position «Скачанное» shortcut and a download-list action. Song menus offer download, cancel or remove depending on state. Album/playlist pages offer «Скачать». The downloads screen groups active/failed transfers separately from completed songs, displays progress and storage use, and offers cancel/retry and confirmed deletion of all local downloads. Completed songs retain scores and can play in score order or shuffle with the existing best-N slider. Removing local audio never removes favorites, playlists, votes or queue entries. Library rows remain compact and the full player remains without scrolling.

An explicit download uses the current network, including mobile data; explain this at the downloads screen. No automatic downloads on playback. No automatic retry/network activity on reopening. No promise of transfers surviving a killed app process.

## Persistence and transfer

SQLite schema 2 adds an account-scoped downloads table without modifying votes/state. Rows store track metadata, random file basename, state, expected/completed size, created time and sanitized errors. Never persist stream URLs or tokens. Audio lives in app-private persistent storage beside the database, outside the cache directory, with no storage permission. Android backup remains disabled.

Download one track at a time; deduplicate account+track. Resolve a fresh authenticated stream URL, then use an independent HTTP client without account credentials for the CDN. Restrict URLs to HTTPS (literal loopback HTTP in debug fixtures only), require successful complete HTTP responses, reject non-audio headers/payload, enforce a 256 MiB per-file bound and bounded network timeouts. Write a random .part file and atomically rename only after completion and validation. Cancel closes the transfer client and removes partial data. Disk-full and network failures preserve a retryable row; continue other queued jobs.

On launch, remove abandoned .part/orphan audio files, mark interrupted work failed, and mark missing or incorrectly sized completed files failed. Completed downloads persist across restarts and APK upgrades. Account changes cancel pending transfers and expose only that account's files. A file-path resolver validates basename, account and size before playback.

## Playback

MusicHandler owns the downloader and configures it with its account/API. Source loading asks for a verified local file before requesting a stream URL, including when API/token is unavailable. Preserve serialized source loading and generation checks. Downloaded-only queues use ordinary playback: seek, automatic advance, repeat, background notification and scores. Mixed queues retain ordinary behavior; a missing online song reports an actionable connection/download error.

## Validation and delivery

Test SQLite v1→v2 preservation, restart persistence, account isolation, cancellation, queue deduplication, malicious/partial HTTP responses, byte limits, storage cleanup and retry. Android emulator tests download known WAV fixtures, stop the source server, recreate the handler, then exercise local seek/next/natural completion and system media controls. Inspect UI at 320×568 and larger text. Verify signed update from 1.9.0 preserves existing rows and downloads. Run regression suite, format/analyze, Ubuntu CI, signed release and secret scan. Install directly over the phone's app if it is connected; never uninstall or integration-test the physical phone.

## Accepted addition: notification score

Show live score after votes from both app and notification, including offline/background playback. Android 7–12 expanded notification uses a decorated custom notification with a genuine minus / score / plus row and the three transport controls in that view. Android 13+ system media cards control their own layout; keep their five controls and put the live score in artist metadata. Carry the score in existing custom-action extras so native equality triggers a refresh; action identities retain stale track/account guards. Verify real custom-view PendingIntents on API 30 and MediaSession actions on API 36. Keep runtime resources after release shrinking.

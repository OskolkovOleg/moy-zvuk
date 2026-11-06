# Music Discovery Implementation Plan

> Execute inline in this chat. The user has authorized implementation.

**Goal:** Four practical discovery modes that help fill the scored library.
**Architecture:** Existing Zvuk API/catalog and player, pure candidate selection,
account-scoped discovery state, one reusable results screen and four hub entries.
**Tech Stack:** Flutter 3.47.6, Dart 3.13.5, existing http/sqflite libraries.
**Spec:** docs/superpowers/specs/2026-11-06-discovery-design.md

## Global constraints

- Never infer music semantics from spelling or unrelated fields.
- Missing dates/explicit/canonical data remain unknown.
- Baseline 9; plus saves; minus never deletes; configuration never starts music.
- Personal data and credentials remain outside Git.
- Preserve dark theme, existing notification and player behavior.

## 1. Candidate selection and persistence

Files: lib/data/discovery_models.dart, discovery_store.dart,
lib/data/models.dart; test/discovery_test.dart, discovery_store_test.dart.

- [x] Add nullable canonicalTrackId to Track API/JSON round trips, preserving all
  metadata in any Track copy. Identity keys include id plus canonical id.
- [x] Implement DiscoveryCandidate(track, reason, source?) and DiscoveryMode,
  verified thematic shelf descriptors and dated release models.
- [x] Test exclusion of known/canonical matches, recent and blocked entries;
  strict explicit=false filtering; round-robin pool diversity and max size20.
- [x] Implement source interleaving with artist diversity and distinct seed
  selection from rankedTracks (positive scores preferred, baseline fallback).
- [x] Persist offers with timestamps (7 days, max2000) and separate blocks through
  state table transactions. Test account isolation and independent resets.

## 2. Verified service sources and generation

Files: lib/data/discovery_api.dart, lib/data/zvuk_api.dart,
lib/discovery_controller.dart; test/discovery_controller_test.dart (API and controller fixtures).

- [x] Test actual artist release query with nullable rows and dates, contextual
  radio, verified playlist sources, and partial failures.
- [x] API getArtists(ids) releases(offset:0,limit:10) date/tracks; existing
  recommendations(WaveSource.fromTrack(seed)) and playlistTracks used directly.
- [x] Generate top-song recommendations using up to5 distinct seeds. Rotate
  seeds between batches; keep provenance captions. By-song uses explicit seed.
- [x] Fresh releases: saved artists then ranked favorite artists, max12 artists;
  actual release date within90 days, no future or undated releases.
- [x] Explore: independent playlist sources, selected style or interleaved
  directions, actual playlist names and source links, no personalized fallback.
- [x] Request-generation and account guards reject stale writes; source failures
  are visible; no result is auto-played or auto-added to favorites.

## 3. UI and queue integration

Files: lib/ui/discovery_screen.dart, discovery_entry.dart,
lib/ui/discover_screen.dart, track_actions.dart,
lib/playback/queue_controls.dart; test/discovery_widget_test.dart.

- [x] Four repeated rows in Обзор with distinct purpose and short description.
- [x] Dedicated result route: seed picker, style chips, censor chip, refresh,
  source captions, hidden-list restore and repeat reset on empty results.
- [x] Playback uses immutable filtered snapshot; shuffle is explicit; append
  deduplicates existing queue and publishes/saves without stopping current song.
- [x] Existing TrackTile handles votes, artist-only navigation and long press;
  discovery action sheet includes Не предлагать and normal track actions.
- [x] Widget fixtures cover queue vs play, stale requests, votes remaining in
  place, errors, empty results, 360dp and320dp/1.6 text captures.

## 4. Release verification

Files: pubspec.yaml, lib/app_version.dart, README.md, docs/reports/ as existing.

- [x] Version1.17.0+29; format/analyze locally, 159 Linux CI tests and UI captures.
- [x] Reviewed current screenshots at360dp and320dp/1.6 text; no overflow, wrapping controls and scroll verified.
- [x] Build ARM64 via existing GitHub workflow, verify artifact and APK, sign with
  existing local certificate, verify16KiB alignment and credential scan.
- [x] Install in-place on connected USB device if present; verify version,
  preserved app data and cold start; record truthful limitations if unavailable.
- [x] Mirror changed source and final artifact to existing private workspace.

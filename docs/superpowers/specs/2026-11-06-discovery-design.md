# Открытия музыки

Approved scope: Oleg accepted the discovery proposal and added a fourth mode for
popular music beyond his established taste, including genre and artist immersion.
This extends the existing Обзор/catalog/queue flows. No external recommender or
new account service is required. Execute in this chat without another approval.

## Four modes

1. По моим лучшим: contextual recommendations from several distinct high-scored
   favorite songs, rotated between batches; no scores are transmitted as ratings.
2. Похоже на песню: choose an actual library song or the currently playing song;
   request its contextual radio. Expose the entry in existing track actions too.
3. Свежие релизы: dated releases within 90 days from saved artists and artists
   represented by the user's best library songs. Missing dates stay unknown.
4. Расширить вкус: catalog chart/editorial playlist sources independent of local
   scores and the personal wave. Разное interleaves several directions; choosing
   Клубная, Электроника, Рок, Хип-хоп, Поп or Инди gives a sustained selection.
   Artist links/open-catalog provide popular songs and albums for deeper listening.
   Genre labels describe verified playlist themes, never guessed track metadata.

## Candidate selection and actions

Generate up to 20 tracks per batch, retaining a human-readable source reason.
Exclude favorites, canonical matches when supplied, explicit blocks and recent
proposals (7 days, bounded at 2000 records); deduplicate within the batch and
interleave source pools with artist diversity. A started track is not proof of a
completed listen. Never call candidates «никогда не слышал».

Selection/loading/refresh never starts playback or adds favorites. Слушать starts
an explicitly chosen batch; Перемешать shuffles a snapshot; В очередь appends
without interrupting current playback. Existing +1/-1 controls and score policy
remain: baseline 9, positive vote adds library; minus never deletes a favorite.
A separate Не предлагать action persists a block. Hidden tracks can be restored.
Refresh can explicitly clear recent proposals without clearing blocks.
Цензурные uses only explicit=false; missing values excluded in that mode.

## Boundaries and failure cases

Discovery models/selector are pure; account-scoped storage uses the existing
SQLite state table, no destructive migration. API extensions use verified GraphQL
fields and fixed Zvuk playlist IDs with source titles read back from service.
One failed source permits the other sources, with a visible partial-result note;
all failed sources show retry. Empty is explicit and permits resetting recent
proposals. Old requests cannot overwrite a newer selection or another account.
No account secrets or personal candidate reports enter Git.

## UI

Обзор gets four consistent entry rows, not four competing hero banners. The
result page uses the current dark theme, existing TrackTile/score/artist targets,
quiet source captions and one group of explicit playback actions. Controls wrap
at narrow width and larger text. State remains stable during votes. Source rows
can open the original playlist/artist. No playback is triggered by configuration.

## Verification

Pure tests: canonical/existing/blocked/recent exclusions, expiry, artist/source
mixing, scores, release dates and malformed API rows. Storage tests: persistence,
account isolation, restoring blocks. API tests: real query shapes and dates.
Widget tests and captures: four modes, narrow/large text, queue semantics,
loading/error/empty, vote stability and source-specific controls. Run format,
analyze and full suite on Linux CI; build signed ARM64 release; install in place
if USB is available, preserving all app data.

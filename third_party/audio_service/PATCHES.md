# Local audio_service 0.18.19 compatibility patch

Runtime source copied from the published pub.dev 0.18.19 archive. The original MIT license is retained. Dart and Darwin sources are unchanged; the example and package test suite are omitted.

Upstream `AudioService.setState` puts custom controls only in MediaSession, omitting them from NotificationCompat actions. Android 7–12 notification layouts therefore lose these buttons. This copy also adds custom notification actions on API < 33, with immutable explicit PendingIntents delivered to a non-exported receiver. The service rejects actions no longer present in its current MediaSession. Android 13+ keeps the upstream custom MediaSession action path.

The app adds `zvukRatingScore` to rating action extras and publishes the live score alongside the artist in MediaItem metadata. All Android versions retain the standard MediaStyle and artwork, so SystemUI supplies the media-card layout, cover palette and transport presentation. On Android 7–12 native NotificationCompat actions include minus/plus; Android 13+ uses MediaSession custom actions. Score changes rebuild metadata/actions without restarting audio. Custom RemoteViews from 1.10.0–1.10.1 were removed after user feedback about their appearance and collapsing behavior.

Changed upstream files:
- android/src/main/java/com/ryanheise/audioservice/AudioService.java
- android/src/main/AndroidManifest.xml

Added: android/src/main/java/com/ryanheise/audioservice/CustomActionReceiver.java.

The app embeds track/account/generation identity in each rating action and reuses its usual vote persistence. Integration coverage: `integration_test/notification_rating_test.dart`, using real Android notification PendingIntents and MediaSession commands on an emulator. Re-evaluate this patch when updating upstream.

The same native custom-action path carries a favorite heart in 1.12.0. The app uses pause/play, next, favorite, minus and plus to fit Android's five slots; previous remains in the full player. Filled/outline Material icons and add/remove labels follow account-scoped favorites. Action identity also includes membership, preventing an old add intent from undoing a completed add, and duplicate writes are suppressed while one is pending. `integration_test/notification_favorite_test.dart` checks both native PendingIntents and the Android 13+ MediaSession path. No additional vendor changes are needed.

References: [audio_service](https://pub.dev/packages/audio_service/versions/0.18.19), [Android media controls](https://developer.android.com/media/implement/surfaces/mobile).

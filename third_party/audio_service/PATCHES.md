# Local audio_service 0.18.19 compatibility patch

Runtime source copied from the published pub.dev 0.18.19 archive. The original MIT license is retained. Dart and Darwin sources are unchanged; the example and package test suite are omitted.

Upstream `AudioService.setState` puts custom controls only in MediaSession, omitting them from NotificationCompat actions. Android 7–12 notification layouts therefore lose these buttons. This copy also adds custom notification actions on API < 33, with immutable explicit PendingIntents delivered to a non-exported receiver. The service rejects actions no longer present in its current MediaSession. Android 13+ keeps the upstream custom MediaSession action path.

The app adds `zvukRatingScore` to rating action extras. On Android 7–12 a decorated custom notification shows a real minus / score / plus row, with previous/play/next in its own transport row. Its explicit PendingIntents use the same stale-action validation. It retains the active MediaSession but avoids MediaStyle on API <33 because Android 11 QS discards custom media views. Layout/IDs live in the host app and are kept/verified after release shrinking. On Android 13+ the system owns the media-card layout; the app publishes the score in the MediaItem artist metadata and retains the standard five controls. Score changes update custom-action equality and rebuild the notification without restarting audio.

Changed upstream files:
- android/src/main/java/com/ryanheise/audioservice/AudioService.java
- android/src/main/AndroidManifest.xml

Added: android/src/main/java/com/ryanheise/audioservice/CustomActionReceiver.java.

The app embeds track/account/generation identity in each rating action and reuses its usual vote persistence. Integration coverage: `integration_test/notification_rating_test.dart`, using real Android notification PendingIntents and MediaSession commands on an emulator. Re-evaluate this patch when updating upstream.

References: [audio_service](https://pub.dev/packages/audio_service/versions/0.18.19), [Android media controls](https://developer.android.com/media/implement/surfaces/mobile).

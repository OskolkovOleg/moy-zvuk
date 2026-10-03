# Local audio_service 0.18.19 compatibility patch

Runtime source copied from the published pub.dev 0.18.19 archive. The original MIT license is retained. Dart and Darwin sources are unchanged; the example and package test suite are omitted.

Upstream `AudioService.setState` puts custom controls only in MediaSession, omitting them from NotificationCompat actions. Android 7–12 notification layouts therefore lose these buttons. This copy also adds custom notification actions on API < 33, with immutable explicit PendingIntents delivered to a non-exported receiver. The service rejects actions no longer present in its current MediaSession. Android 13+ keeps the upstream custom MediaSession action path.

Changed upstream files:
- android/src/main/java/com/ryanheise/audioservice/AudioService.java
- android/src/main/AndroidManifest.xml

Added: android/src/main/java/com/ryanheise/audioservice/CustomActionReceiver.java.

The app embeds track/account/generation identity in each rating action and reuses its usual vote persistence. Integration coverage: `integration_test/notification_rating_test.dart`, using real Android notification PendingIntents and MediaSession commands on an emulator. Re-evaluate this patch when updating upstream.

References: [audio_service](https://pub.dev/packages/audio_service/versions/0.18.19), [Android media controls](https://developer.android.com/media/implement/surfaces/mobile).

package dev.oleg.zvuk_personal

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Notification
import android.app.NotificationManager
import android.media.session.MediaController
import android.media.session.MediaSession

/** Debug-only lifecycle bridge used by the Android integration suite. */
class TestActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "zvuk.test").setMethodCallHandler { call, result ->
            if (call.method == "background") {
                moveTaskToBack(true)
                result.success(null)
            } else if (call.method == "notification") {
                val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                val active = manager.activeNotifications.firstOrNull { it.notification.category == Notification.CATEGORY_TRANSPORT }
                val notification = active?.notification
                result.success(mapOf(
                    "present" to (notification != null),
                    "foreground" to ((notification?.flags ?: 0) and Notification.FLAG_FOREGROUND_SERVICE != 0),
                    "ongoing" to ((notification?.flags ?: 0) and Notification.FLAG_ONGOING_EVENT != 0),
                    "actions" to (notification?.actions?.map { it.title.toString() } ?: emptyList<String>()),
                    "title" to notification?.extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                ))
            } else if (call.method == "mediaCommand") {
                val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                val notification = manager.activeNotifications.firstOrNull { it.notification.category == Notification.CATEGORY_TRANSPORT }?.notification
                @Suppress("DEPRECATION")
                val token = notification?.extras?.getParcelable<MediaSession.Token>(Notification.EXTRA_MEDIA_SESSION)
                if (token == null) {
                    result.error("NO_SESSION", "No media notification session", null)
                } else {
                    val controls = MediaController(this, token).transportControls
                    when (call.arguments as String) {
                        "pause" -> controls.pause()
                        "play" -> controls.play()
                        "next" -> controls.skipToNext()
                        "previous" -> controls.skipToPrevious()
                        "stop" -> controls.stop()
                    }
                    result.success(null)
                }
            } else result.notImplemented()
        }
    }
}

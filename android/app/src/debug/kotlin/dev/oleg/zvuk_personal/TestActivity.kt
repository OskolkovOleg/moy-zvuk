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
                @Suppress("DEPRECATION")
                val token = notification?.extras?.getParcelable<MediaSession.Token>(Notification.EXTRA_MEDIA_SESSION)
                val state = token?.let { MediaController(this, it).playbackState }
                result.success(mapOf(
                    "present" to (notification != null),
                    "foreground" to ((notification?.flags ?: 0) and Notification.FLAG_FOREGROUND_SERVICE != 0),
                    "ongoing" to ((notification?.flags ?: 0) and Notification.FLAG_ONGOING_EVENT != 0),
                    "actions" to (notification?.actions?.map { it.title.toString() } ?: emptyList<String>()),
                    "title" to notification?.extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
                    "customActions" to (state?.customActions?.map { it.action } ?: emptyList<String>()),
                    "customLabels" to (state?.customActions?.map { it.name.toString() } ?: emptyList<String>()),
                    "customIcons" to (state?.customActions?.map { it.icon } ?: emptyList<Int>()),
                    "ratingScore" to notification?.extras?.getInt("zvukRatingScore"),
                    "hasCustomView" to (notification?.contentView != null || notification?.bigContentView != null),
                    "style" to notification?.extras?.getString("android.template"),
                    "subtitle" to notification?.extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
                    "hasArtwork" to (notification?.getLargeIcon() != null),
                    "sdk" to android.os.Build.VERSION.SDK_INT
                ))
            } else if (call.method == "notificationAction" || call.method == "customMediaAction") {
                val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                val notification = manager.activeNotifications.firstOrNull { it.notification.category == Notification.CATEGORY_TRANSPORT }?.notification
                if (call.method == "notificationAction") {
                    val action = notification?.actions?.firstOrNull { it.title.toString() == call.arguments as String }
                    if (action == null) result.error("NO_ACTION", "Missing notification action", null)
                    else {
                        action.actionIntent.send()
                        result.success(null)
                    }
                } else {
                    @Suppress("DEPRECATION")
                    val token = notification?.extras?.getParcelable<MediaSession.Token>(Notification.EXTRA_MEDIA_SESSION)
                    if (token == null) result.error("NO_SESSION", "No media session", null)
                    else {
                        val controller = MediaController(this, token)
                        val action = controller.playbackState?.customActions?.firstOrNull { it.name.toString() == call.arguments as String }
                        if (action == null) result.error("NO_ACTION", "Missing media action", null)
                        else {
                            controller.transportControls.sendCustomAction(action, action.extras)
                            result.success(null)
                        }
                    }
                }
            } else if (call.method == "notificationTransport") {
                val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                val notification = manager.activeNotifications.firstOrNull { it.notification.category == Notification.CATEGORY_TRANSPORT }?.notification
                val label = when (call.arguments as String) {
                    "previous" -> "Previous"
                    "next" -> "Next"
                    "pause" -> "Pause"
                    "play" -> "Play"
                    else -> ""
                }
                val action = notification?.actions?.firstOrNull { it.title.toString() == label }
                if (action == null) result.error("NO_ACTION", "Missing transport action", null)
                else {
                    action.actionIntent.send()
                    result.success(null)
                }
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

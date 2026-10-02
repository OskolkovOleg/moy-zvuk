import 'package:audio_service/audio_service.dart';

const musicServiceConfig = AudioServiceConfig(
  androidNotificationChannelId: 'dev.oleg.zvuk_personal.playback',
  androidNotificationChannelName: 'Музыка',
  androidNotificationChannelDescription:
      'Плеер: пауза, переключение и остановка',
  androidNotificationIcon: 'drawable/ic_stat_music',
  // Keep the foreground service and its media controls through pauses and
  // source changes. The notification's Stop action explicitly ends it.
  androidStopForegroundOnPause: false,
  androidNotificationOngoing: false,
  artDownscaleWidth: 320,
  artDownscaleHeight: 320,
);

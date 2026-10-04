import 'package:audio_service/audio_service.dart';

const musicServiceConfig = AudioServiceConfig(
  androidNotificationChannelId: 'dev.oleg.zvuk_personal.playback',
  androidNotificationChannelName: 'Музыка',
  androidNotificationChannelDescription:
      'Плеер: пауза, следующая песня, избранное и оценки −1 / +1',
  androidNotificationIcon: 'drawable/ic_stat_music',
  // Keep the foreground service and its media controls through pauses and
  // source changes. Rating actions never interrupt playback.
  androidStopForegroundOnPause: false,
  androidNotificationOngoing: false,
  artDownscaleWidth: 320,
  artDownscaleHeight: 320,
);

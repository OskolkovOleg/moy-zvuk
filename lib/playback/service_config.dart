import 'package:audio_service/audio_service.dart';

const musicServiceConfig = AudioServiceConfig(
  androidNotificationChannelId: 'dev.oleg.zvuk_personal.playback',
  androidNotificationChannelName: 'Музыка',
  androidNotificationChannelDescription:
      'Плеер: пауза, следующая песня, избранное и оценки −1 / +1',
  androidNotificationIcon: 'drawable/ic_stat_music',
  // Release foreground priority on pause so Android can dismiss the media card.
  // Loading keeps PlaybackState.playing true through automatic track changes.
  androidStopForegroundOnPause: true,
  androidNotificationOngoing: false,
  artDownscaleWidth: 320,
  artDownscaleHeight: 320,
);

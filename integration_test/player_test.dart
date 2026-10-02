// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/playback/music_handler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Real background handler, queue, media controls and restore', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Проверка плеера'))),
    );
    final response = await http.get(
      Uri.parse('http://127.0.0.1:18746/credential'),
    );
    final api = ZvukApi(jsonDecode(response.body)['token']);
    final directory = await Directory.systemTemp.createTemp('zvuk-player-test');
    final store = await LibraryStore.open(
      databasePath: '${directory.path}/test.db',
    );
    final handler = await AudioService.init<MusicHandler>(
      builder: () => MusicHandler(store),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.oleg.zvuk_personal.test',
        androidNotificationChannelName: 'Проверка плеера',
        androidNotificationIcon: 'drawable/ic_stat_music',
      ),
    );
    await handler.initialize();
    await handler.configure('test', api);
    await handler.player.setVolume(0);
    final tracks = await api.tracks(['177981965', '180082552']);
    try {
      await handler.playList(tracks, 0);
      await handler.player.positionStream
          .firstWhere((p) => p.inSeconds >= 2)
          .timeout(const Duration(seconds: 40));
      final queueBefore = handler.playlist.tracks.map((t) => t.id).toList();
      await store.vote('test', tracks.last, 1);
      expect(handler.playlist.tracks.map((t) => t.id), queueBefore);
      await const MethodChannel('zvuk.test').invokeMethod<void>('background');
      final before = handler.player.position;
      await Future<void>.delayed(const Duration(seconds: 6));
      expect(handler.player.playing, true);
      expect(
        handler.player.position,
        greaterThan(before + const Duration(seconds: 3)),
      );
      print('BACKGROUND_AUDIO passed');
      await handler.skipToNext();
      expect(handler.playlist.current!.id, tracks.last.id);
      await handler.seek(handler.player.duration! - const Duration(seconds: 2));
      await handler.player.processingStateStream
          .firstWhere((s) => s.name == 'completed')
          .timeout(const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(handler.player.playing, false);
      expect(handler.playlist.index, 1);
      await handler.skipToPrevious();
      await handler.seek(const Duration(seconds: 12));
      await handler.pause();
      await handler.configure('other', null);
      await handler.configure('test', api);
      expect(handler.player.playing, false);
      expect(handler.playlist.tracks, hasLength(2));
      expect(handler.playbackState.value.position.inSeconds, 12);
      print('HANDLER queue=passed completion=passed restorePaused=passed');
    } finally {
      await handler.disposeHandler();
      await store.close();
      api.close();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

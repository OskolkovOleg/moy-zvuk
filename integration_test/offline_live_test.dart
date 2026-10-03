// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/downloads/download_manager.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';

import 'background_controls_test.dart' show until;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Real Zvuk songs download and play from local files without API',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Проверка офлайн-музыки'))),
      );
      final credential = jsonDecode(
        (await http.get(Uri.parse('http://127.0.0.1:18746/credential'))).body,
      ) as Map<String, dynamic>;
      final api = ZvukApi(credential.remove('token') as String);
      final directory = await Directory.systemTemp.createTemp(
        'zvuk-offline-live',
      );
      final store = await LibraryStore.open(
        databasePath: '${directory.path}/test.db',
      );
      final manager = DownloadManager(store);
      final tracks = await api.tracks(['177981965', '180082552']);
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      try {
        expect(tracks, hasLength(2));
        await manager.configure('live-offline', api);
        await manager.enqueue(tracks);
        await until(() => manager.pendingCount == 0, seconds: 120);
        expect(manager.tracks, hasLength(2));
        expect(manager.storedBytes, greaterThan(1024 * 1024));
        final rows = await store.db.query('downloads');
        expect(rows.toString(), isNot(contains('/api/')));
        expect(rows.toString(), isNot(contains('X-Auth-Token')));
        await manager.close();
        api.close();
        await music.initialize();
        await music.configure('live-offline', null);
        await music.player.setVolume(0);
        await music.playList(tracks, 0, title: 'Скачанное');
        await until(
          () => music.player.playing && music.player.duration != null,
        );
        await music.seek(music.player.duration! - const Duration(seconds: 1));
        await until(
          () =>
              music.playlist.index == 1 &&
              music.player.playing &&
              !music.loading,
        );
        expect(music.error.value, isNull);
        print(
          'LIVE OFFLINE: two complete MP3 downloads, sanitized manifest, API-null playback, seek and natural next passed',
        );
      } finally {
        await music.disposeHandler();
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

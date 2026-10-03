// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';

import 'background_controls_test.dart' show silence, until;

class WaveClipApi extends ZvukApi {
  WaveClipApi(this.port, http.Client client) : super('fixture', client: client);
  final int port;
  @override
  Future<String> streamUrl(String id) async => 'http://127.0.0.1:$port/$id.wav';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Wave extends, completes naturally, persists, and cancels delayed starts',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final directory = await Directory.systemTemp.createTemp('zvuk-wave-test');
      final store = await LibraryStore.open(
        databasePath: '${directory.path}/test.db',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.headers.contentType = ContentType('audio', 'wav');
        req.response.add(silence(2));
        await req.response.close();
      });
      var calls = 0;
      Completer<void>? hold;
      final api = WaveClipApi(
        server.port,
        MockClient((req) async {
          final batch = calls++;
          if (hold != null) await hold.future;
          return http.Response(
            jsonEncode({
              'data': {
                'personalWaveContent': List.generate(
                  2,
                  (i) => {
                    'id': 'wave-$batch-$i',
                    'title': 'Wave $batch $i',
                    'duration': 2,
                  },
                ),
              },
            }),
            200,
          );
        }),
      );
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      try {
        await music.initialize();
        await music.configure('wave-test', api);
        await music.player.setVolume(0);
        await music.startWave();
        await until(
          () =>
              music.playlist.index >= 3 &&
              music.player.playing &&
              !music.loading,
        );
        expect(music.isWave, true);
        expect(
          music.playbackState.value.systemActions,
          contains(MediaAction.setRepeatMode),
        );
        expect(calls, greaterThanOrEqualTo(3));
        expect(music.error.value, isNull);
        await music.pause();
        await music.savePosition();
        expect((await store.get('wave-test', 'queue') as Map)['wave'], true);
        await music.configure('other', api);
        await music.configure('wave-test', api);
        expect(music.isWave, true);
        expect(music.player.playing, false);
        hold = Completer<void>();
        final before = music.playlist.current!.id;
        final pending = music.startWave();
        await until(() => music.loading);
        await music.pause();
        hold.complete();
        await pending;
        expect(music.player.playing, false);
        expect(music.playlist.current!.id, before);
        hold = Completer<void>();
        final replaced = music.startWave();
        await until(() => music.loading);
        await music.playList(const [
          Track(id: 'manual', title: 'Manual', duration: 2),
        ], 0);
        hold.complete();
        await replaced;
        expect(music.isWave, false);
        expect(music.playlist.current!.id, 'manual');
        await music.pause();
        print(
          'WAVE natural extension, persistence, pause cancellation, manual replacement: passed',
        );
      } finally {
        await music.disposeHandler();
        api.close();
        await server.close(force: true);
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

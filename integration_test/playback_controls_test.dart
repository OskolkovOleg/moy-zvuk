// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';

import 'background_controls_test.dart' show silence, until;

class ControlsApi extends ZvukApi {
  ControlsApi(this.port, http.Client client) : super('fixture', client: client);
  final int port;
  Completer<void>? gate;
  int requests = 0;
  @override
  Future<String> streamUrl(String id) async {
    requests++;
    final wait = gate;
    if (wait != null) await wait.future;
    return 'http://127.0.0.1:$port/$id.wav';
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Queue edits, natural repeat, sleep in background and stale wave cancellation',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Проверка режимов плеера')),
        ),
      );
      final dir = await Directory.systemTemp.createTemp('zvuk-controls');
      final store = await LibraryStore.open(
        databasePath: '${dir.path}/test.db',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType('audio', 'wav');
        request.response.add(
          silence(request.uri.path.contains('short') ? 1 : 20),
        );
        await request.response.close();
      });
      var waveCalls = 0;
      final waveGate = Completer<http.Response>();
      final api = ControlsApi(
        server.port,
        MockClient((req) async {
          final b = jsonDecode(req.body);
          if (b['operationName'] == 'getPersonalWave') {
            waveCalls++;
            if (waveCalls > 1) return waveGate.future;
            return http.Response(
              jsonEncode({
                'data': {
                  'personalWaveContent': [
                    {'id': 'wave', 'title': 'Wave'},
                  ],
                },
              }),
              200,
            );
          }
          return http.Response('{}', 503);
        }),
      );
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      StreamSubscription<ProcessingState>? completed;
      const first = Track(id: 'short1', title: 'First', duration: 1),
          second = Track(id: 'short2', title: 'Second', duration: 1);
      const long = Track(id: 'long', title: 'Long', duration: 20);
      const bridge = MethodChannel('zvuk.test');
      try {
        await music.initialize();
        await music.configure('controls', api);
        await music.player.setVolume(0);
        var finishes = 0;
        completed = music.player.processingStateStream.listen((state) {
          if (state == ProcessingState.completed) finishes++;
        });
        await music.setRepeatMode(AudioServiceRepeatMode.one);
        await music.playList([first, second], 0);
        await until(() => finishes >= 2);
        expect(music.playlist.current!.id, first.id);
        expect(music.nextTrack!.id, first.id);
        await music.skipToNext();
        expect(music.playlist.current!.id, second.id);
        await music.pause();
        await music.setRepeatMode(AudioServiceRepeatMode.all);
        await music.playList([first, second], 1);
        await until(() => music.playlist.index == 0 && music.player.playing);
        expect(
          music.playbackState.value.repeatMode,
          AudioServiceRepeatMode.all,
        );
        await music.skipToPrevious();
        expect(music.playlist.index, 1);
        await music.pause();
        await music.configure('other', api);
        await music.configure('controls', api);
        expect(music.repeatMode, AudioServiceRepeatMode.all);
        expect(music.player.playing, false);
        await music.setRepeatMode(AudioServiceRepeatMode.none);
        print(
          'REPEAT one natural loops, manual skip, all wraps next/previous and restores paused: passed',
        );

        await music.playList([long, first, second, long, second], 0);
        await until(() => music.player.position.inMilliseconds > 200);
        final calls = api.requests,
            version = music.playlist.version,
            key = music.playlist.entryKey(0),
            pos = music.position;
        expect(await music.moveInQueue(0, 2, version), true);
        expect(music.playlist.entryKey(music.playlist.index), key);
        expect(music.playbackState.value.queueIndex, 2);
        expect(music.position, greaterThanOrEqualTo(pos));
        expect(api.requests, calls);
        expect(await music.removeFromQueue(0, version), false);
        expect(await music.removeFromQueue(0, music.playlist.version), true);
        expect(music.playlist.entryKey(music.playlist.index), key);
        expect(api.requests, calls);
        await music.shuffleUpcoming();
        expect(music.playlist.entryKey(music.playlist.index), key);
        expect(music.player.playing, true);
        await music.pause();
        final next = music.playlist.tracks[music.playlist.index + 1].id;
        await music.removeFromQueue(
          music.playlist.index,
          music.playlist.version,
        );
        expect(music.playlist.current!.id, next);
        expect(music.player.playing, false);
        await music.playList([long], 0);
        await until(() => music.player.playing);
        await music.removeFromQueue(0, music.playlist.version);
        expect(music.playlist.current, isNull);
        expect(music.player.playing, false);
        expect(music.player.processingState, ProcessingState.idle);
        print(
          'QUEUE reorder/removal preserve occurrence/audio; stale edits rejected; paused and empty cases: passed',
        );

        await music.setRepeatMode(AudioServiceRepeatMode.one);
        music.sleepAfterSong();
        await music.playList([first, second], 0);
        await until(() => !music.player.playing && !music.loading);
        expect(music.playlist.index, 0);
        expect(music.sleepTimer.active, false);
        await music.setRepeatMode(AudioServiceRepeatMode.none);
        await music.playList([long, second], 0);
        await until(() => music.player.playing);
        music.setSleepTimer(const Duration(milliseconds: 400));
        await bridge.invokeMethod<void>('background');
        await until(() => !music.player.playing, seconds: 5);
        expect(music.sleepTimer.active, false);
        expect(music.playlist.index, 0);
        final gate = Completer<void>();
        api.gate = gate;
        final pending = music.playList([long], 0);
        music.setSleepTimer(const Duration(milliseconds: 300));
        await until(() => !music.sleepTimer.active, seconds: 5);
        gate.complete();
        api.gate = null;
        await pending;
        expect(music.player.playing, false);
        expect(music.loading, false);
        print(
          'SLEEP end-song wins over repeat; timed pause in background and delayed source cancellation: passed',
        );

        await music.startWave();
        await until(() => waveCalls > 1);
        expect(music.isWave, true);
        expect(music.nextTrack, isNull);
        expect(music.upNextTitle, 'Поток подберёт следующую');
        await music.clearUpcoming();
        waveGate.complete(
          http.Response(
            jsonEncode({
              'data': {
                'personalWaveContent': [
                  {'id': 'late', 'title': 'Late'},
                ],
              },
            }),
            200,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(music.isWave, false);
        expect(music.playlist.length, 1);
        expect(music.repeatMode, AudioServiceRepeatMode.none);
        expect(music.upNextTitle, 'Очередь завершится без повтора');
        print(
          'WAVE final preview is safe; clear remaining cancels late refill: passed',
        );
      } finally {
        if (!waveGate.isCompleted) {
          waveGate.complete(
            http.Response('{"data":{"personalWaveContent":[]}}', 200),
          );
        }
        if (api.gate?.isCompleted == false) api.gate!.complete();
        await completed?.cancel();
        await music.disposeHandler();
        api.close();
        await server.close(force: true);
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

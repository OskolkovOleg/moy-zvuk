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
import 'package:zvuk_personal/data/wave_options.dart';
import 'package:zvuk_personal/data/wave_source.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';

import 'radio_playback_test.dart' show RadioFixtureApi;
import 'background_controls_test.dart' show silence, until;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Tuner preserves audio, cancels old batches and persists per account',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final dir = await Directory.systemTemp.createTemp('wave-tuner');
      final store = await LibraryStore.open(
        databasePath: '${dir.path}/test.db',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        r.response.headers.contentType = ContentType('audio', 'wav');
        r.response.add(silence(30));
        await r.response.close();
      });
      Completer<void>? gate;
      bool gated = false, failGated = false;
      final requests = <Map<String, dynamic>>[];
      final api = RadioFixtureApi(
        server.port,
        'fixture',
        client: MockClient((r) async {
          final b = jsonDecode(r.body) as Map<String, dynamic>;
          final n = requests.length;
          requests.add(b);
          final wait = gate;
          if (wait != null && !gated) {
            gated = true;
            await wait.future;
            if (failGated) return http.Response('{}', 503);
          }
          final filtered = b['variables']['options'] != null;
          final tracks = List.generate(
            6,
            (i) => {
              'id': '${filtered ? 'new' : 'old'}-$n-$i',
              'title': 'Song $i',
              'duration': 30,
            },
          );
          return http.Response(
            jsonEncode({
              'data': {
                'personalWaveContent': tracks,
                'recommenderRadio': {'tracks': tracks, 'cursor': 6},
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
      const options = WaveOptions(
        mood: WaveMood.energetic,
        language: WaveLanguage.russian,
        genres: ['rock'],
      );
      try {
        await music.initialize();
        await music.configure('one', api);
        await music.player.setVolume(0);
        await music.startWave();
        await until(() => music.player.playing && !music.loading);
        await music.seek(const Duration(seconds: 4));
        final key = music.playlist.entryKey(music.playlist.index);
        final streams = api.streams;
        gate = Completer<void>();
        await music.setWaveOptions(
          const WaveOptions(language: WaveLanguage.foreign),
        );
        await until(() => gated);
        await music.setWaveOptions(options);
        await until(() => music.playlist.hasNext);
        gate.complete();
        gate = null;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(music.playlist.entryKey(music.playlist.index), key);
        expect(api.streams, streams);
        expect(music.position.inSeconds, greaterThanOrEqualTo(4));
        expect(music.player.playing, true);
        expect(
          music.playlist.tracks
              .skip(music.playlist.index + 1)
              .every((t) => t.id.startsWith('new-')),
          true,
        );
        expect(requests.last['variables']['options'], options.toApi());
        await music.seek(const Duration(seconds: 29));
        await until(
          () => music.playlist.current!.id.startsWith('new-') && !music.loading,
        );
        await music.pause();
        final paused = music.playlist.current!.id;
        await music.setWaveOptions(
          const WaveOptions(popularity: WavePopularity.hits),
        );
        await until(() => music.playlist.hasNext);
        expect(music.player.playing, false);
        expect(music.playlist.current!.id, paused);
        await music.savePosition();
        await music.configure('two', api);
        expect(music.waveOptions.isDefault, true);
        await music.configure('one', api);
        expect(music.waveOptions.popularity, WavePopularity.hits);
        expect(music.isWave, true);
        expect(music.player.playing, false);
        print(
          'WAVE TUNER current stream/entry/position, stale batch, natural next, paused restore and account isolation passed',
        );
        await music.startWave();
        gated = false;
        failGated = true;
        gate = Completer<void>();
        await music.setWaveOptions(
          const WaveOptions(language: WaveLanguage.foreign),
        );
        await until(() => gated);
        final next = music.skipToNext();
        await until(() => music.loading);
        await music.setWaveOptions(options);
        await until(() => music.playlist.hasNext);
        gate.complete();
        gate = null;
        await next;
        expect(music.player.playing, true);
        expect(music.loading, false);
        expect(music.error.value, isNull);
        expect(music.playlist.current!.id.startsWith('new-'), true);
        print(
          'WAVE TUNER next waiting for an obsolete failed batch retries with new options passed',
        );
        await music.startWave(source: const WaveSource.favorites());
        final queue = music.playlist.toJson();
        await music.setWaveOptions(options);
        expect(music.playlist.toJson(), queue);
        expect(requests.last['variables'].containsKey('options'), false);
        await music.playList([
          const Track(id: 'manual', title: 'Manual', duration: 30),
        ], 0);
        final manual = music.playlist.toJson();
        await music.setWaveOptions(const WaveOptions());
        expect(music.playlist.toJson(), manual);
        print('WAVE TUNER favorites and manual queues unchanged passed');
      } finally {
        if (gate != null && !gate.isCompleted) gate.complete();
        await music.disposeHandler();
        api.close();
        await server.close(force: true);
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

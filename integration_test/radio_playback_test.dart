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
import 'package:zvuk_personal/data/wave_source.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';

import 'background_controls_test.dart' show silence, until;

class RadioFixtureApi extends ZvukApi {
  RadioFixtureApi(this.port, super.token, {super.client});
  final int port;
  int streams = 0;
  Completer<void>? streamGate;
  @override
  Future<String> streamUrl(String id) async {
    streams++;
    final wait = streamGate;
    if (wait != null) await wait.future;
    return 'http://127.0.0.1:$port/$id.wav';
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Context source persists, extends and cancels; append keeps audio',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final dir = await Directory.systemTemp.createTemp('zvuk-radio-playback');
      final store = await LibraryStore.open(
        databasePath: '${dir.path}/test.db',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        r.response.headers.contentType = ContentType('audio', 'wav');
        r.response.add(silence(r.uri.path.contains('long') ? 20 : 1));
        await r.response.close();
      });
      var calls = 0, empty = false, append = false;
      Completer<void>? gate;
      final requests = <Map<String, dynamic>>[];
      final api = RadioFixtureApi(
        server.port,
        'fixture',
        client: MockClient((req) async {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          requests.add(b);
          final n = calls++;
          final wait = gate;
          if (wait != null) await wait.future;
          final tracks = empty
              ? <Object>[]
              : append
              ? [
                  {'id': 'long', 'title': 'Existing'},
                  {'id': 'seed', 'title': 'Seed'},
                  {'id': 'added', 'title': 'Added'},
                  {'id': 'added', 'title': 'Duplicate'},
                ]
              : [
                  {'id': 'seed', 'title': 'Seed'},
                  ...List.generate(
                    2,
                    (i) => {
                      'id': 'radio-$n-$i',
                      'title': 'Radio $n $i',
                      'duration': 1,
                    },
                  ),
                ];
          return http.Response(
            jsonEncode({
              'data': {
                'recommenderRadio': {'tracks': tracks, 'cursor': 2},
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
      const seed = WaveSource(
        kind: WaveKind.track,
        id: 'seed',
        title: 'Основа',
      );
      const long = Track(id: 'long', title: 'Long', duration: 20);
      try {
        await music.initialize();
        await music.configure('fixture', api);
        await music.player.setVolume(0);
        await music.startWave(source: seed);
        await until(() => music.playlist.index >= 3 && !music.loading);
        expect(music.playlist.tracks.any((t) => t.id == 'seed'), false);
        expect(
          requests.every(
            (r) =>
                r['variables']['id'] == 'seed' &&
                r['variables']['type'] == 'TRACK',
          ),
          true,
        );
        expect(
          requests.skip(1).every((r) => r['variables']['cursor'] == 2),
          true,
        );
        await music.pause();
        await music.savePosition();
        await music.configure('other', api);
        await music.configure('fixture', api);
        expect(music.isWave, true);
        expect(music.waveSource.id, 'seed');
        expect(music.player.playing, false);
        await music.skipToQueueItem(music.playlist.length - 1);
        await until(() => requests.length > 3);
        await music.pause();
        print(
          'RADIO original seed, natural extension, repeating cursor and paused restore: passed',
        );
        gate = Completer<void>();
        final pending = music.startWave(source: seed);
        await until(() => music.loading);
        await music.cancelWaveStart(seed);
        gate.complete();
        await pending;
        expect(music.player.playing, false);
        expect(music.isWave, false);
        gate = null;
        // Cancel before pause/save finishes, not only during the network request.
        final early = music.startWave(source: seed);
        await music.cancelWaveStart(seed);
        await early;
        expect(music.isWave, false);
        expect(music.player.playing, false);
        api.streamGate = Completer<void>();
        final loadingStream = music.startWave(source: seed);
        await until(() => music.isWave && music.loading);
        await music.cancelWaveStart(seed);
        api.streamGate!.complete();
        await loadingStream;
        api.streamGate = null;
        expect(music.player.playing, false);
        expect(music.isWave, false);
        await music.playList([long], 0);
        await until(() => music.player.playing && !music.loading);
        await music.seek(const Duration(seconds: 3));
        append = true;
        final key = music.playlist.entryKey(0), streams = api.streams;
        expect(
          await music.appendSimilar(const Track(id: 'seed', title: 'Seed')),
          1,
        );
        expect(music.playlist.entryKey(music.playlist.index), key);
        expect(api.streams, streams);
        expect(music.player.playing, true);
        expect(music.position.inSeconds, greaterThanOrEqualTo(3));
        expect(music.playlist.tracks.map((t) => t.id), ['long', 'added']);
        gate = Completer<void>();
        final before = calls;
        final stale = music.appendSimilar(
          const Track(id: 'seed', title: 'Seed'),
        );
        final rejected = expectLater(stale, throwsA(isA<ZvukException>()));
        await until(() => calls > before);
        await music.enqueueTrack(const Track(id: 'manual', title: 'Manual'));
        gate.complete();
        await rejected;
        gate = null;
        expect(music.playlist.length, 3);
        expect(
          await music.appendSimilar(
            const Track(id: 'seed', title: 'Seed'),
            cancelled: () => true,
          ),
          0,
        );
        await music.pause();
        empty = true;
        await music.startWave(source: seed);
        expect(music.error.value, isNotNull);
        expect(music.playlist.current!.id, 'long');
        expect(music.player.playing, false);
        print(
          'RADIO delayed/early cancel, append without restart, stale append and empty source: passed',
        );
        final saved =
            await store.get('fixture', 'queue') as Map<String, dynamic>;
        await music.configure('other', api);
        await store.put('fixture', 'queue', {
          ...saved,
          'wave': true,
          'waveSource': {'kind': 'bad'},
        });
        await music.configure('fixture', api);
        expect(music.isWave, false);
        expect(music.playlist.current!.id, 'long');
        print('RADIO corrupt metadata preserves cached queue: passed');
        await music.configure('other', api);
        final legacy = {...saved, 'wave': true}
          ..remove('waveSource')
          ..remove('waveCursor');
        await store.put('fixture', 'queue', legacy);
        await music.configure('fixture', api);
        expect(music.isWave, true);
        expect(music.waveSource.kind, WaveKind.personal);
        expect(music.player.playing, false);
        print('RADIO legacy personal wave restore: passed');
      } finally {
        if (gate != null && !gate.isCompleted) gate.complete();
        if (api.streamGate != null && !api.streamGate!.isCompleted) {
          api.streamGate!.complete();
        }
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

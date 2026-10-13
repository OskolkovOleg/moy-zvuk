// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/data/audio_preferences.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';

import 'background_controls_test.dart' show silence, until;
import '../test/download_manager_test.dart' show waitDownloads;

class RecoveryApi extends ZvukApi {
  RecoveryApi(this.port) : super('fixture');
  final int port;
  final calls = <String, int>{};
  Completer<void>? gate;
  @override
  Future<String> streamUrl(
    String id, {
    AudioQuality quality = AudioQuality.high,
  }) async {
    final count = calls.update(id, (n) => n + 1, ifAbsent: () => 1);
    if (id == 'blocked') {
      throw const ZvukException(
        'Synthetic connection failure',
        retryable: true,
      );
    }
    if (id == 'missing') {
      throw const ZvukException('Synthetic unavailable song');
    }
    if (id == 'delayed' && gate != null) await gate!.future;
    final path = id == 'expired' && count == 1
        ? 'forbidden'
        : id == 'runtime' && count == 1
        ? 'interrupted'
        : id;
    return 'http://127.0.0.1:$port/$path.wav';
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Mixed queue recovery, fresh URLs, repeat bounds and cancellation',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final directory = await Directory.systemTemp.createTemp('zvuk-recovery');
      final store = await LibraryStore.open(
        databasePath: '${directory.path}/test.db',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var interruptedRequests = 0;
      server.listen((request) async {
        if (request.uri.path == '/interrupted.wav') {
          if (interruptedRequests++ > 0) {
            request.response.statusCode = 403;
            await request.response.close();
          } else {
            final data = silence(40);
            request.response.headers.contentType = ContentType('audio', 'wav');
            request.response.contentLength = data.length;
            request.response.add(data.sublist(0, 320000));
            await request.response.flush();
            await Future<void>.delayed(const Duration(seconds: 3));
            try {
              await request.response.close();
            } catch (_) {}
          }
          return;
        }
        if (request.uri.path == '/forbidden.wav') {
          request.response.statusCode = 403;
        } else {
          request.response.headers.contentType = ContentType('audio', 'wav');
          request.response.add(silence(20));
        }
        await request.response.close();
      });
      final api = RecoveryApi(server.port);
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      const cached = Track(id: 'cached', title: 'Скачанная', duration: 20);
      const cached2 = Track(
        id: 'cached2',
        title: 'Следующая скачанная',
        duration: 20,
      );
      const missing = Track(id: 'missing', title: 'Недоступная');
      const blocked = Track(id: 'blocked', title: 'Нет соединения');
      const fresh = Track(id: 'fresh', title: 'Доступная онлайн', duration: 20);
      try {
        await music.initialize();
        await music.configure('recovery', api);
        await music.player.setVolume(0);
        await music.downloads.enqueue([cached, cached2]);
        await waitDownloads(music.downloads);
        expect(music.downloads.tracks, hasLength(2));
        await store.vote('recovery', cached, -1);
        await store.saveOrder('recovery', 'favorites', ['cached2', 'cached']);
        api.calls.clear();
        await music.playList([blocked, fresh, cached, missing, cached2], 0);
        await until(() => music.player.playing && !music.loading);
        expect(music.playlist.index, 2);
        expect(api.calls, {'blocked': 1});
        expect(music.error.value, isNull);
        await music.seek(const Duration(seconds: 19));
        await until(
          () =>
              music.playlist.index == 4 &&
              music.player.playing &&
              !music.loading,
        );
        expect(api.calls, {'blocked': 1});
        expect(music.playlist.tracks.map((t) => t.id), [
          'blocked',
          'fresh',
          'cached',
          'missing',
          'cached2',
        ]);
        expect((await store.ratings('recovery'))['cached']!.score, 9);
        expect(await store.loadOrder('recovery', 'favorites'), [
          'cached2',
          'cached',
        ]);
        print(
          'RECOVERY: connection failure skips remote holes and continues cached queue, including automatic next; data preserved',
        );

        await music.playList([missing, fresh], 0);
        await until(() => music.player.playing && !music.loading);
        expect(music.playlist.current!.id, 'fresh');
        expect(api.calls['fresh'], 1);
        api.calls.clear();
        const expired = Track(
          id: 'expired',
          title: 'Устаревший адрес',
          duration: 20,
        );
        await music.playList([expired, cached], 0);
        await until(() => music.player.playing && !music.loading);
        expect(music.playlist.current!.id, 'expired');
        expect(api.calls['expired'], 2);
        print(
          'RECOVERY: unavailable track skipped, expired CDN URL replaced with fresh URL for same song',
        );

        api.calls.clear();
        const runtime = Track(
          id: 'runtime',
          title: 'Обрыв во время песни',
          duration: 40,
        );
        await music.playList([runtime, cached], 0);
        await until(
          () => music.player.playing && music.position.inMilliseconds > 200,
        );
        final runtimeKey = music.playlist.entryKey(music.playlist.index);
        await until(
          () =>
              api.calls['runtime'] == 2 &&
              music.player.playing &&
              !music.loading,
          seconds: 35,
        );
        expect(music.playlist.current!.id, 'runtime');
        expect(music.playlist.entryKey(music.playlist.index), runtimeKey);
        expect(music.position.inSeconds, greaterThanOrEqualTo(1));
        expect(music.error.value, isNull);
        print(
          'RECOVERY: real interrupted HTTP stream resumes same occurrence at preserved position with fresh URL',
        );

        await music.setRepeatMode(AudioServiceRepeatMode.all);
        api.calls.clear();
        await music.playList([blocked, missing], 0);
        expect(music.player.playing, false);
        expect(music.loading, false);
        expect(music.error.value, isNotNull);
        expect(api.calls, {'blocked': 1});
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(api.calls, {'blocked': 1});
        await music.setRepeatMode(AudioServiceRepeatMode.none);

        api.gate = Completer<void>();
        final pending = music.playList([
          const Track(id: 'delayed', title: 'Ожидающая'),
          cached,
        ], 0);
        await until(() => api.calls.containsKey('delayed'));
        await music.pause();
        api.gate!.complete();
        await pending;
        expect(music.player.playing, false);
        expect(music.playlist.index, 0);
        expect(music.error.value, isNull);
        api.gate = Completer<void>();
        final old = music.play();
        await until(() => api.calls['delayed'] == 2);
        final replacement = music.playList([cached2], 0);
        api.gate!.complete();
        await Future.wait([old, replacement]);
        await until(() => music.player.playing && !music.loading);
        expect(music.playlist.current!.id, 'cached2');
        print(
          'RECOVERY: repeat-all stops with no playable entries; pause and replacement reject late responses',
        );

        await music.configure('recovery', null);
        await music.playList([missing, cached, fresh, cached2], 0);
        await until(() => music.player.playing && !music.loading);
        expect(music.playlist.current!.id, 'cached');
        await music.seek(const Duration(seconds: 19));
        await until(
          () =>
              music.playlist.current!.id == 'cached2' &&
              music.player.playing &&
              !music.loading,
        );
        expect(music.downloads.tracks, hasLength(2));
        print(
          'RECOVERY: mixed downloaded/non-downloaded list plays offline with no API',
        );
      } finally {
        if (api.gate != null && !api.gate!.isCompleted) api.gate!.complete();
        await music.disposeHandler();
        api.close();
        await server.close(force: true);
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

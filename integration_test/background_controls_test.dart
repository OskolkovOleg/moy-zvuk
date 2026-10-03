// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/data/audio_preferences.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';

class ClipApi extends ZvukApi {
  ClipApi(this.port) : super('test-credential');
  final int port;
  @override
  Future<String> streamUrl(
    String id, {
    AudioQuality quality = AudioQuality.high,
  }) async => 'http://127.0.0.1:$port/$id.wav';
}

Uint8List silence(int seconds) {
  final samples = 16000 * seconds;
  final bytes = Uint8List(44 + samples * 2);
  final data = ByteData.sublistView(bytes);
  void text(int at, String value) =>
      bytes.setRange(at, at + value.length, value.codeUnits);
  text(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  return bytes;
}

Future<void> until(bool Function() predicate, {int seconds = 20}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(predicate(), true);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Natural background completion, media notification and rapid skips',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Проверка фонового плеера')),
        ),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType('audio', 'wav');
        request.response.add(silence(request.uri.path == '/first.wav' ? 3 : 8));
        await request.response.close();
      });
      final directory = await Directory.systemTemp.createTemp(
        'zvuk-background-test',
      );
      final store = await LibraryStore.open(
        databasePath: '${directory.path}/test.db',
      );
      final api = ClipApi(server.port);
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      const bridge = MethodChannel('zvuk.test');
      Future<Map<dynamic, dynamic>> notification() async =>
          (await bridge.invokeMapMethod<dynamic, dynamic>('notification'))!;
      try {
        await music.initialize();
        await music.configure('background-test', api);
        await music.player.setVolume(0);
        await music.playList(const [
          Track(id: 'first', title: 'First', duration: 3),
          Track(id: 'second', title: 'Second', duration: 8),
        ], 0);
        await until(() => music.player.position.inMilliseconds > 150);
        await bridge.invokeMethod<void>('background');
        // Let the first file play completely; no seek or synthetic completed event.
        await until(
          () =>
              music.playlist.index == 1 &&
              !music.loading &&
              music.player.playing,
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final playingNotification = await notification();
        expect(playingNotification['present'], true);
        expect(playingNotification['foreground'], true);
        expect(
          (playingNotification['actions'] as List).length,
          greaterThanOrEqualTo(3),
        );
        expect(playingNotification['title'], 'Second');
        await bridge.invokeMethod<void>('mediaCommand', 'pause');
        await until(() => !music.player.playing);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect((await notification())['present'], true);
        expect((await notification())['foreground'], true);
        await bridge.invokeMethod<void>('mediaCommand', 'play');
        await until(() => music.player.playing);
        await until(() => !music.player.playing && !music.loading);
        expect(music.playlist.index, 1);
        print(
          'NATURAL_NEXT passed NOTIFICATION present=passed persistentPause=passed mediaControls=passed endStops=passed',
        );
        final large = List.generate(
          2000,
          (i) => Track(
            id: 'stress-$i',
            title: 'Track $i with a long title for the system media queue',
            artists: 'Artist with a long display name',
            imageUrl: 'https://example.com/${'cover-' * 20}$i.jpg',
            duration: 8,
          ),
        );
        await music.playList(large, 0);
        final skips = <Future<void>>[];
        for (var i = 0; i < 25; i++) {
          skips.add(music.skipToNext());
        }
        await Future.wait(skips);
        await until(() => !music.loading && music.player.playing);
        expect(music.playlist.index, 25);
        expect(music.error.value, isNull);
        expect(music.playlist.tracks, hasLength(2000));
        await music.pause();
        print('RAPID_SKIPS 25 of 2000 passed');
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

// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/data/audio_preferences.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';
import 'package:zvuk_personal/ui/player_sheet.dart';
import 'package:zvuk_personal/ui/theme.dart';
import 'package:zvuk_personal/ui/widgets.dart';

import 'background_controls_test.dart' as clips;

class FavoriteFixtureState {
  FavoriteFixtureState(this.likes);
  final Set<String> likes;
  bool failWrite = false, failRead = false;
  Completer<void>? hold;
  int writes = 0;

  Future<http.Response> mutate(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['operationName'], 'changeCollection');
    final id = body['variables']['id'] as String;
    final liked = (body['query'] as String).contains('addItem(');
    writes++;
    if (hold != null) await hold!.future;
    if (failWrite) return http.Response('{}', 503);
    if (liked) {
      likes.add(id);
    } else {
      likes.remove(id);
    }
    return http.Response(
      jsonEncode({
        'data': {
          'collection': {liked ? 'addItem' : 'removeItem': null},
        },
      }),
      200,
    );
  }
}

class FavoriteFixtureApi extends ZvukApi {
  factory FavoriteFixtureApi(int port, List<Track> songs, Set<String> likes) =>
      FavoriteFixtureApi._(port, songs, FavoriteFixtureState(likes));
  FavoriteFixtureApi._(this.port, this.songs, this.state)
    : super('favorite-fixture', client: MockClient(state.mutate));
  final int port;
  final List<Track> songs;
  final FavoriteFixtureState state;

  @override
  Future<String> streamUrl(
    String id, {
    AudioQuality quality = AudioQuality.high,
  }) async => 'http://127.0.0.1:$port/$id.wav';

  @override
  Future<List<Track>> favorites() async {
    if (state.failRead) throw const ZvukException('Нет сети');
    return songs.where((t) => state.likes.contains(t.id)).toList();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Favorite hearts preserve score, queue and compact player', (
    tester,
  ) async {
    const a = Track(
      id: 'favorite-ui-a',
      title: 'Ночная дорога',
      artists: 'Тестовый артист',
      duration: 60,
    );
    const b = Track(
      id: 'favorite-ui-b',
      title: 'Длинное название новой песни',
      artists: 'Другой артист',
      duration: 60,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add(clips.silence(60));
      await request.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('zvuk-favorite-ui');
    final store = await LibraryStore.open(databasePath: '${dir.path}/test.db');
    final api = FavoriteFixtureApi(server.port, [a, b], {a.id});
    final music = await AudioService.init<MusicHandler>(
      builder: () => MusicHandler(store),
      config: musicServiceConfig,
    );
    final app = AppController(store, music)
      ..account = const Account('favorite-ui', 'Тест')
      ..api = api
      ..favoriteTracks = [a]
      ..tracks = [a, b]
      ..listId = 'fixture-playlist'
      ..ranked = true;
    Finder heart(Track t) => find.byKey(ValueKey('favorite:${t.id}'));
    void checkHeart(Track t, bool filled) {
      final icon = tester.widget<Icon>(
        find.descendant(of: heart(t), matching: find.byType(Icon)),
      );
      expect(
        icon.icon,
        filled ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      );
    }

    Future<void> settleEdit() async {
      await clips.until(() => !app.serverBusy);
      await tester.pumpAndSettle();
    }

    try {
      await store.saveTracks('favorite-ui', 'favorites', [a]);
      await store.saveOrder('favorite-ui', 'fixture-playlist', [b.id, a.id]);
      for (var i = 0; i < 13; i++) {
        await app.vote(a, -1);
      }
      await music.initialize();
      await music.configure('favorite-ui', api);
      await music.player.setVolume(0);
      await music.playList([a, b], 0);
      await music.pause();
      await music.seek(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final position = music.position;
      final source = music.player.sequence.first;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    TrackTile(
                      track: a,
                      app: app,
                      onPlay: () => fail('Favorite must not play'),
                    ),
                    TrackTile(
                      track: b,
                      app: app,
                      onPlay: () => fail('Favorite must not play'),
                    ),
                    TextButton(
                      onPressed: () => openPlayer(context, app),
                      child: const Text('Открыть плеер'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      checkHeart(a, true);
      checkHeart(b, false);
      expect(
        tester.getSize(find.byType(TrackTile).first).height,
        lessThanOrEqualTo(60),
      );
      await binding.takeScreenshot('v112-01-hearts');

      api.state.hold = Completer<void>();
      await tester.tap(heart(b));
      await tester.pump();
      await clips.until(() => app.serverBusy);
      await tester.pump();
      await tester.tap(heart(b));
      await tester.pump();
      expect(api.state.writes, 1);
      api.state.hold!.complete();
      api.state.hold = null;
      await settleEdit();
      checkHeart(b, true);
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text('Открыть плеер'));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollable), findsNothing);
      api.state.failRead = true;
      await tester.tap(heart(a));
      await tester.pump();
      await settleEdit();
      checkHeart(a, false);
      expect(
        (await store.loadTracks('favorite-ui', 'favorites')).map((t) => t.id),
        [b.id],
      );
      expect(app.scoreFor(a), -3);
      expect((await store.ratings('favorite-ui'))[a.id]!.score, -3);
      expect(await store.loadOrder('favorite-ui', 'fixture-playlist'), [
        b.id,
        a.id,
      ]);
      expect(music.player.sequence.first, same(source));
      expect(music.playlist.tracks.map((t) => t.id), [a.id, b.id]);
      expect(music.position, position);
      expect(music.player.playing, false);
      expect(find.byType(SnackBar), findsNothing);
      await binding.takeScreenshot('v112-02-player-heart');
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(heart(a).hitTestable(), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
      await binding.takeScreenshot('v112-03-player-large-text');
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      api.state.failRead = false;
      api.state.failWrite = true;
      await tester.tap(heart(a));
      await tester.pump();
      await settleEdit();
      checkHeart(a, false);
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.tap(find.byTooltip('Свернуть плеер'));
      await tester.pumpAndSettle();
      checkHeart(a, false);
      checkHeart(b, true);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('v112-04-hearts-large-text');
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.longPress(find.text(b.title));
      await tester.pumpAndSettle();
      expect(find.text('В конец очереди'), findsOneWidget);
      expect(tester.takeException(), isNull);
      print(
        'FAVORITE UI: narrow rows, full player, large text, duplicate tap, API failure, committed cache, quiet success, negative votes and playback preservation passed',
      );
    } finally {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await music.disposeHandler();
      api.close();
      await server.close(force: true);
      await store.close();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

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
import 'package:zvuk_personal/ui/app.dart';
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
  Future<List<String>> favoriteIds() async {
    if (state.failRead) throw const ZvukException('Нет сети');
    return state.likes.toList();
  }

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
  testWidgets(
    'Plus collects an outside song, rating-only UI and score range stay compact',
    (tester) async {
      const a = Track(
        id: 'favorite-ui-a',
        title: 'Ночная дорога',
        artists: 'Тестовый артист',
        duration: 60,
      );
      const b = Track(
        id: 'favorite-ui-b',
        title: 'Новая песня с длинным названием',
        artists: 'Другой артист',
        duration: 60,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        r.response.add(clips.silence(60));
        await r.response.close();
      });
      final dir = await Directory.systemTemp.createTemp('score-ui');
      final store = await LibraryStore.open(
        databasePath: '${dir.path}/test.db',
      );
      final api = FavoriteFixtureApi(server.port, [a, b], {a.id});
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      final app = AppController(store, music)
        ..account = const Account('score-ui', 'Тест')
        ..api = api
        ..favoriteTracks = [a]
        ..tracks = [a];
      try {
        await store.saveTracks('score-ui', 'favorites', [a]);
        await music.initialize();
        await music.configure('score-ui', api);
        await music.player.setVolume(0);
        await music.playList([b, a], 0);
        await clips.until(() => music.position.inMilliseconds > 250);
        final originalQueue = music.playlist.tracks.map((t) => t.id).toList();
        await tester.pumpWidget(
          MaterialApp(theme: appTheme(), home: PlayerSheet(app)),
        );
        await tester.pumpAndSettle();
        expect(app.scoreFor(b), 9);
        expect(find.byKey(ValueKey('favorite:${b.id}')), findsNothing);
        final before = music.position;
        await tester.tap(find.byTooltip('Плюс один: ${b.title}'));
        await clips.until(() => app.scoreFor(b) == 10);
        await app.syncLibraryAdds();
        await tester.pumpAndSettle();
        expect(app.isFavorite(b.id), true);
        expect(api.state.likes, contains(b.id));
        expect(api.state.writes, 1);
        expect(music.player.playing, true);
        expect(music.position, greaterThanOrEqualTo(before));
        expect(music.playlist.tracks.map((t) => t.id), originalQueue);
        expect(music.playlist.index, 0);
        expect(find.byType(SnackBar), findsNothing);
        expect(music.playbackState.value.controls, hasLength(5));
        expect(
          music.playbackState.value.controls
              .where((c) => c.customAction != null)
              .map((c) => c.label),
          ['Минус 1 балл', 'Плюс 1 балл'],
        );
        expect(
          await music.customAction('zvuk.favorite.add:0:score-ui:${b.id}'),
          false,
        );
        await tester.tap(find.byTooltip('Минус один: ${b.title}'));
        await tester.pumpAndSettle();
        expect(app.scoreFor(b), 9);
        expect(app.isFavorite(b.id), true);
        expect(api.state.writes, 1);
        await music.pause();
        await app.vote(b, -1);
        await app.vote(b, -1);
        await tester.pumpWidget(ZvukApp(app));
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        expect(app.visibleTracks.map((t) => t.id), [a.id, b.id]);
        expect(find.text('Мой порядок'), findsNothing);
        expect(find.text('Без оценок'), findsNothing);
        expect(find.textContaining('Старт'), findsNothing);
        expect(find.byKey(ValueKey('favorite:${a.id}')), findsNothing);
        expect(
          tester.getSize(find.byType(TrackTile).first).height,
          lessThanOrEqualTo(80),
        );
        await binding.takeScreenshot('v140-score-library-normal');
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('v140-score-library-large');
        await tester.tap(find.byKey(const Key('shuffle-list')));
        await tester.pumpAndSettle();
        final slider = tester.widget<RangeSlider>(
          find.byKey(const Key('shuffle-score-slider')),
        );
        expect(slider.values, const RangeValues(7, 9));
        final sliderBox = tester.getRect(
          find.byKey(const Key('shuffle-score-slider')),
        );
        await tester.dragFrom(
          Offset(sliderBox.left + 24, sliderBox.center.dy),
          Offset((sliderBox.width - 48) / 2, 0),
        );
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.text('Подходит 1 трек'), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('shuffle-min'))).data,
          '8',
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('shuffle-max'))).data,
          '9',
        );
        await binding.takeScreenshot('v140-score-range-large');
        await tester.tap(find.byKey(const Key('start-shuffle')));
        await tester.pump();
        await clips.until(() => music.player.playing && !music.loading);
        expect(music.playlist.tracks.single.id, a.id);
        expect(music.isShuffled, true);
        await music.pause();
        expect(tester.takeException(), isNull);
        print(
          'SCORE UI: new song 9 -> 10 and collected once; minus keeps membership; playback preserved; no hearts/manual/unrated; compact rows and two-thumb range passed',
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
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

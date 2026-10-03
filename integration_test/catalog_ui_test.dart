// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/catalog_detail_screen.dart';
import 'package:zvuk_personal/ui/catalog_widgets.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Catalog, search, details, collection edits and narrow UI', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('zvuk-catalog-ui');
    final store = await LibraryStore.open(databasePath: '${dir.path}/test.db');
    final music = await AudioService.init<MusicHandler>(
      builder: () => MusicHandler(store),
      config: musicServiceConfig,
    );
    await music.initialize();
    final song = <String, dynamic>{
      'id': 't',
      'title': 'Ночная дорога',
      'artists': [
        {'id': 'a', 'title': 'Тестовый артист'},
      ],
      'release': {'id': 'r'},
      'duration': 180,
    };
    final lists = <String, Map<String, dynamic>>{
      'p': {
        'id': 'p',
        'title': 'Вечерний плейлист',
        'userId': 'fixture',
        'tracks': [
          {'id': 't'},
        ],
      },
    };
    final likes = <String>{};
    var waveRequests = 0;
    final api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        final b = req.method == 'POST'
            ? jsonDecode(req.body)
            : <String, dynamic>{};
        final v = b['variables'] ?? <String, dynamic>{};
        dynamic result;
        switch (b['operationName']) {
          case 'catalogSearch':
            final query = b['query'] as String;
            final field = [
              'tracks',
              'artists',
              'releases',
              'playlists',
            ].firstWhere((f) => query.contains('$f(limit:'));
            result = {
              'search': {
                field: {
                  'page': {},
                  'items': [
                    switch (field) {
                      'tracks' => song,
                      'artists' => {'id': 'a', 'title': 'Тестовый артист'},
                      'releases' => {
                        'id': 'r',
                        'title': 'Новый альбом',
                        'artists': [
                          {'id': 'a', 'title': 'Тестовый артист'},
                        ],
                      },
                      _ => lists['p'],
                    },
                  ],
                },
              },
            };
          case 'catalogDetail':
            result = (b['query'] as String).contains('getArtists')
                ? {
                    'getArtists': [
                      {
                        'id': 'a',
                        'title': 'Тестовый артист',
                        'popularTracks': [song],
                        'releases': [
                          {'id': 'r', 'title': 'Новый альбом'},
                        ],
                      },
                    ],
                  }
                : {
                    'getReleases': [
                      {
                        'id': 'r',
                        'title': 'Новый альбом',
                        'tracks': [song],
                      },
                    ],
                  };
          case 'getPlaylists':
            result = {
              'getPlaylists': (v['ids'] as List)
                  .map(
                    (id) =>
                        lists[id] ??
                        {
                          'id': id,
                          'title': id == '1062105'
                              ? 'Топ 100'
                              : id == '6'
                              ? 'Когда хочется музыки'
                              : 'Подборка Звука',
                          'tracks': [
                            {'id': 't'},
                          ],
                        },
                  )
                  .toList(),
            };
          case 'getPlaylistTracks':
            result = {
              'playlistTracks': [song],
            };
          case 'getTracks':
            result = {
              'getTracks': likes.isEmpty ? [] : [song],
            };
          case 'userCollection':
            result = {
              'collection': {
                'tracks': likes.map((id) => {'id': id}).toList(),
              },
            };
          case 'userPlaylists':
            result = {
              'collection': {
                'playlists': lists.keys.map((id) => {'id': id}).toList(),
              },
            };
          case 'changeCollection':
            final adding = (b['query'] as String).contains('addItem(');
            adding ? likes.add(v['id']) : likes.remove(v['id']);
            result = {
              'collection': {adding ? 'addItem' : 'removeItem': null},
            };
          case 'createPlayList':
            lists['new'] = {
              'id': 'new',
              'title': v['name'],
              'userId': 'fixture',
              'tracks': [],
            };
            result = {
              'playlist': {'create': 'new'},
            };
          case 'addTracksToPlaylist':
            result = {
              'playlist': {'addItems': null},
            };
          case 'setPlaylistToPublic':
            lists[v['id']]!['isPublic'] = v['isPublic'];
            result = {
              'playlist': {'setPublic': null},
            };
          case 'renamePlaylist':
            lists[v['id']]!['title'] = v['name'];
            result = {
              'playlist': {'rename': null},
            };
          case 'deletePlaylist':
            lists.remove(v['id']);
            result = {
              'playlist': {'delete': null},
            };
          case 'getPersonalWave':
            waveRequests++;
            result = {
              'personalWaveContent': [song],
            };
          default:
            if (req.url.path.contains('/grid/')) {
              return http.Response(
                jsonEncode({
                  'result': {
                    'page': {
                      'data': [
                        {'type': 'playlist', 'id': 'p'},
                      ],
                    },
                  },
                }),
                200,
              );
            }
            return http.Response('{}', 503);
        }
        return http.Response(
          jsonEncode({'data': result}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await music.configure('fixture', api);
    final app = AppController(store, music)
      ..account = const Account('fixture', 'Тест')
      ..api = api;
    app.tracks = [Track.fromApi(song)];
    app.playlists = lists.values.map(PlaylistInfo.fromJson).toList();
    Future<void> tab(String name) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(name),
        ),
      );
      await tester.pumpAndSettle();
    }

    try {
      await tester.pumpWidget(ZvukApp(app));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await tab('Обзор');
      expect(find.text('Включить поток'), findsOneWidget);
      await binding.takeScreenshot('v140-01-discover');
      await tab('Поиск');
      await tester.tap(find.text('Треки'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Музыка');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Ночная дорога'), findsOneWidget);
      await tester.tap(find.byTooltip('Действия: Ночная дорога'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В любимое'));
      await tester.pumpAndSettle();
      expect(app.isFavorite('t'), true);
      await tester.tap(find.text('Артисты'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CatalogTile));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Альбомы и синглы'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Альбомы и синглы'), findsOneWidget);
      await binding.takeScreenshot('v140-02-artist');
      await tester.tap(find.text('Новый альбом'));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogDetailScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Альбомы'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Альбомы'));
      await tester.pumpAndSettle();
      expect(find.text('Новый альбом'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Плейлисты'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Плейлисты'));
      await tester.pumpAndSettle();
      expect(find.text('Вечерний плейлист'), findsOneWidget);
      await binding.takeScreenshot('v140-03-search');
      await tab('Плейлисты');
      await tester.tap(find.text('Создать плейлист'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).hitTestable(), 'Мой новый');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(app.playlists.any((p) => p.title == 'Мой новый'), true);
      await tester.tap(find.text('Мой новый'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Плейлист'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переименовать'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).hitTestable(),
        'Другой вечер',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(app.playlists.any((p) => p.title == 'Другой вечер'), true);
      await tester.tap(find.byTooltip('Плейлист'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить плейлист'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(app.playlists.any((p) => p.id == 'new'), false);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      await tab('Обзор');
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('v140-04-discover-large-text');
      await tab('Поиск');
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('v140-05-search-large-text');
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tab('Обзор');
      await tester.tap(find.text('Включить поток'));
      await tester.pumpAndSettle();
      expect(waveRequests, greaterThan(0));
      expect(music.isWave, true);
      print(
        'CATALOG UI four categories, artist/album, like, create/rename/delete, wave, 1.6x text: passed',
      );
    } finally {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpWidget(const SizedBox());
      await music.disposeHandler();
      app.dispose();
      api.close();
      await store.close();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

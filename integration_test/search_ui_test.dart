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
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/search_history_store.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/search_screen.dart';

import 'background_controls_test.dart' show silence;
import 'radio_playback_test.dart' show RadioFixtureApi;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Live typing, mixed results, history, paging, retry and account isolation',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('zvuk-search-ui');
      final store = await LibraryStore.open(
        databasePath: '${dir.path}/test.db',
      );
      final history = SearchHistoryStore(store);
      await history.record('fixture', 'Саян');
      await history.record('fixture', 'Мальборо');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        r.response.headers.contentType = ContentType('audio', 'wav');
        r.response.add(silence(20));
        await r.response.close();
      });
      var failSearch = false;
      Completer<void>? hold;
      final queries = <String>[];
      Map<String, dynamic> track(String id, String title) => {
        '__typename': 'Track',
        'id': id,
        'title': title,
        'duration': 20,
        'artists': [
          {'id': 'a', 'title': 'Тестовый артист'},
        ],
        'release': {'id': 'r'},
      };
      final api = RadioFixtureApi(
        server.port,
        'fixture',
        client: MockClient((req) async {
          final b = jsonDecode(req.body), v = b['variables'] as Map;
          Map<String, dynamic> d;
          switch (b['operationName']) {
            case 'quickSearch':
              queries.add(v['query'] as String);
              final wait = hold;
              if (wait != null) await wait.future;
              if (failSearch) return http.Response('{}', 503);
              d = {
                'quickSearch': {
                  'content': v['query'] == 'пусто'
                      ? []
                      : [
                          track('1', 'Ночная дорога'),
                          {
                            '__typename': 'Artist',
                            'id': 'a',
                            'title': 'Тестовый артист',
                          },
                          track('2', 'Ветер в городе'),
                          {
                            '__typename': 'Release',
                            'id': 'r',
                            'title': 'Вечерний альбом',
                            'artists': [
                              {'title': 'Тестовый артист'},
                            ],
                          },
                          {
                            '__typename': 'Playlist',
                            'id': '42',
                            'title': 'Музыка для дороги',
                          },
                        ],
                },
              };
            case 'catalogSearch':
              final more = v['cursor'] != null;
              d = {
                'search': {
                  'tracks': {
                    'items': more
                        ? [track('3', 'Новая песня')]
                        : [track('1', 'Ночная дорога')],
                    'page': {
                      'next': more ? null : 30,
                      'cursor': more ? null : 'next-page',
                    },
                  },
                },
              };
            case 'catalogDetail':
              d = {
                'getArtists': [
                  {
                    'id': 'a',
                    'title': 'Тестовый артист',
                    'popularTracks': [track('1', 'Ночная дорога')],
                    'releases': [],
                  },
                ],
              };
            default:
              return http.Response('{}', 503);
          }
          return http.Response(
            jsonEncode({'data': d}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      final app = AppController(store, music)
        ..account = const Account('fixture', 'Тест')
        ..api = api;
      Finder field() => find.descendant(
        of: find.byType(SearchScreen),
        matching: find.byType(TextField),
      );
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder.first);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(finder.first);
        await tester.pump();
      }

      Future<void> settleSearch() async {
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
      }

      Future<void> clear() async {
        await tap(find.byTooltip('Очистить поиск'));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }

      try {
        await music.initialize();
        await music.configure('fixture', api);
        await music.player.setVolume(0);
        await tester.pumpWidget(ZvukApp(app));
        await tester.pumpAndSettle();
        await tap(find.text('Поиск'));
        await tester.pumpAndSettle();
        expect(find.text('Мальборо'), findsOneWidget);
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('v180-01-history');
        await tester.enterText(field(), 'ночь');
        await settleSearch();
        expect(queries.last, 'ночь');
        expect(find.text('Ночная дорога'), findsOneWidget);
        expect(await history.recent('fixture'), ['Мальборо', 'Саян']);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await binding.takeScreenshot('v180-02-mixed');
        await tap(find.byKey(const ValueKey('artist:a')));
        await tester.pumpAndSettle();
        expect(find.text('Слушать похожее'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect((await history.recent('fixture')).first, 'ночь');
        await tester.drag(
          find.byType(CustomScrollView).last,
          const Offset(0, 350),
        );
        await tester.pumpAndSettle();
        await tap(find.text('Ночная дорога'));
        await tester.pumpAndSettle();
        expect(music.playlist.current?.id, '1');
        expect(music.playlist.length, 2);
        await music.pause();
        await tap(find.text('Треки'));
        await settleSearch();
        await tap(find.text('Показать ещё'));
        await settleSearch();
        expect(find.text('Новая песня'), findsOneWidget);
        expect(find.text('Показать ещё'), findsNothing);
        await clear();
        await tap(find.text('Мальборо'));
        await settleSearch();
        expect(tester.widget<TextField>(field()).controller!.text, 'Мальборо');
        await clear();
        await tap(find.byTooltip('Удалить запрос «Саян»'));
        await tester.pumpAndSettle();
        expect((await history.recent('fixture')).contains('Саян'), false);
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        await tester.pumpAndSettle();
        await binding.takeScreenshot('v180-03-history-large');
        await tap(find.text('Очистить'));
        await tester.pumpAndSettle();
        expect(await history.recent('fixture'), isEmpty);
        await tap(find.text('Всё'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Всё'))
              .selected,
          true,
        );
        failSearch = true;
        await tester.enterText(field(), 'ошибка');
        await settleSearch();
        await binding.takeScreenshot('v180-04-error-large');
        expect(queries.last, 'ошибка');
        expect(find.text('Повторить'), findsOneWidget);
        expect(tester.takeException(), isNull);
        failSearch = false;
        await tap(find.text('Повторить'));
        await settleSearch();
        expect(find.text('Повторить'), findsNothing);
        await tester.enterText(field(), 'пусто');
        await settleSearch();
        expect(find.text('Ничего не нашлось'), findsOneWidget);
        await binding.takeScreenshot('v180-05-empty-large');
        await clear();
        hold = Completer<void>();
        await tester.enterText(field(), 'старый аккаунт');
        await tester.pump(const Duration(milliseconds: 450));
        expect(queries.last, 'старый аккаунт');
        app.account = const Account('other', 'Другой');
        app.api = null;
        // The root rebuilds on account/connection changes in normal operation.
        await tester.pumpWidget(ZvukApp(app));
        await tester.pumpAndSettle();
        await tap(find.text('Поиск'));
        await tester.pumpAndSettle();
        hold.complete();
        hold = null;
        await tester.pumpAndSettle();
        expect(find.text('Найди своё'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SearchScreen),
            matching: find.text('Ночная дорога'),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        print(
          'SEARCH UI: mixed results, playback, artist, history, paging, errors, large text and account isolation passed',
        );
      } finally {
        if (hold != null && !hold.isCompleted) hold.complete();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpWidget(const SizedBox());
        await music.disposeHandler();
        app.dispose();
        api.close();
        await server.close(force: true);
        await store.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

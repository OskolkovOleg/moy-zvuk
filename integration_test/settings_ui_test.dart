// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/audio_preferences.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/playback/music_handler.dart';
import 'package:zvuk_personal/playback/service_config.dart';
import 'package:zvuk_personal/ui/app.dart';
import 'package:zvuk_personal/ui/settings_screen.dart';
import 'package:zvuk_personal/ui/settings_widgets.dart';
import 'package:zvuk_personal/ui/theme.dart';

import 'background_controls_test.dart' show ClipApi, silence, until;

class QualityApi extends ClipApi {
  QualityApi(super.port);
  final requests = <(String, AudioQuality)>[];
  @override
  Future<String> streamUrl(
    String id, {
    AudioQuality quality = AudioQuality.high,
  }) async {
    requests.add((id, quality));
    return super.streamUrl(id, quality: quality);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Settings change quality without interrupting audio, persist and fit large text',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'zvuk-settings-ui',
      );
      final store = await LibraryStore.open(
        databasePath: '${directory.path}/test.db',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final audio = silence(240);
      server.listen((request) async {
        request.response.headers.contentType = ContentType('audio', 'wav');
        request.response.contentLength = audio.length;
        request.response.add(audio);
        await request.response.close();
      });
      final api = QualityApi(server.port);
      final music = await AudioService.init<MusicHandler>(
        builder: () => MusicHandler(store),
        config: musicServiceConfig,
      );
      const songs = [
        Track(
          id: 'one',
          title: 'Ночная дорога',
          artists: 'Тестовый артист',
          duration: 240,
        ),
        Track(
          id: 'two',
          title: 'Тёплый вечер',
          artists: 'Тестовый артист',
          duration: 240,
        ),
      ];
      final app = AppController(store, music)
        ..account = const Account('settings-ui', 'Тестовый слушатель')
        ..api = api
        ..tracks = songs;
      Future<void> tap(Finder finder) async {
        if (finder.evaluate().isEmpty) {
          final scrollable = find.descendant(
            of: find.byKey(const Key('settings-list')),
            matching: find.byType(Scrollable),
          );
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pump();
          await tester.scrollUntilVisible(
            finder,
            220,
            scrollable: find.descendant(
              of: find.byKey(const Key('settings-list')),
              matching: find.byType(Scrollable),
            ),
          );
        }
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> screenshot(String name) async {
        await tester.pump();
        await binding.takeScreenshot(name);
      }

      try {
        await music.initialize();
        await music.player.setVolume(0);
        await music.configure('settings-ui', api);
        await store.saveTracks('settings-ui', 'favorites', songs);
        await app.vote(songs.first, 1);
        await music.playList(songs, 0, title: 'Проверка настроек');
        await until(() => music.player.position.inMilliseconds > 300);
        await tester.pumpWidget(ZvukApp(app));
        await tester.pump(const Duration(seconds: 1));
        await tap(find.byTooltip('Настройки'));
        expect(find.byType(SettingsScreen), findsOneWidget);
        await binding.convertFlutterSurfaceToImage();
        await screenshot('v111-01-settings');
        final position = music.position;
        await tap(find.byKey(const Key('settings-stream-quality')));
        await screenshot('v111-02-quality');
        await tap(find.byKey(const Key('quality-mid')));
        await until(
          () => music.audioPreferences.streaming == AudioQuality.economy,
        );
        expect(music.player.playing, true);
        expect(music.playlist.current!.id, 'one');
        expect(music.position, greaterThanOrEqualTo(position));
        expect(api.requests, [('one', AudioQuality.high)]);
        expect(music.audioPreferences.downloads, AudioQuality.high);

        await tap(find.byKey(const Key('settings-download-quality')));
        await tap(find.byKey(const Key('quality-mid')));
        await until(
          () => music.audioPreferences.downloads == AudioQuality.economy,
        );
        await music.downloads.enqueue([songs.first]);
        await until(() => music.downloads.pendingCount == 0);
        expect(music.downloads.tracks.single.id, 'one');
        expect(api.requests.last, ('one', AudioQuality.economy));
        await music.skipToNext();
        expect(api.requests.last, ('two', AudioQuality.economy));
        expect(music.playlist.current!.id, 'two');

        final imported = await app.importRatings(
          jsonEncode({
            'version': 1,
            'account': 'settings-ui',
            'events': [
              {
                'id': 'settings-import-vote',
                'track': 'two',
                'delta': 1,
                'created': DateTime.now().toUtc().toIso8601String(),
                'undone': false,
                'metadata': songs.last.toJson(),
              },
            ],
          }),
        );
        expect(imported, 1);
        expect(music.mediaItem.value!.artist, contains('Баллы: 11'));
        expect(music.player.playing, true);

        await tap(find.byKey(const Key('settings-repeat')));
        await tap(find.byKey(const Key('settings-repeat-one')));
        expect(music.repeatMode, AudioServiceRepeatMode.one);
        await tap(find.byKey(const Key('settings-sleep')));
        await tap(find.text('Через 15 мин'));
        expect(music.sleepTimer.active, true);
        music.cancelSleepTimer();
        await tap(find.byKey(const Key('settings-sort')));
        await tap(find.text('По баллам').last);
        expect(app.ranked, true);
        expect(music.playlist.current!.id, 'two');
        expect(music.playlist.tracks.map((t) => t.id), ['one', 'two']);

        await tap(find.byKey(const Key('settings-downloads')));
        expect(find.text('Скачанное'), findsWidgets);
        await tester.tap(find.byType(BackButton).last);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 400));
        await tap(find.byKey(const Key('settings-wave')));
        expect(find.text('Настроить поток'), findsOneWidget);
        await tester.tap(find.byType(BackButton).last);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 400));

        await music.pause();
        await music.configure('other-settings-ui', null);
        expect(music.audioPreferences.streaming, AudioQuality.high);
        await music.configure('settings-ui', api);
        expect(music.audioPreferences.streaming, AudioQuality.economy);
        expect(music.audioPreferences.downloads, AudioQuality.economy);
        expect(music.downloads.tracks.single.id, 'one');
        expect((await store.ratings('settings-ui'))['one']!.score, 11);
        final reopened = await LibraryStore.open(
          databasePath: '${directory.path}/test.db',
        );
        expect(await reopened.get('settings-ui', 'audioPreferences'), {
          'streaming': 'mid',
          'downloads': 'mid',
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('Настройки')),
              body: SettingsScreen(app),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        for (final key in [
          'settings-stream-quality',
          'settings-repeat',
          'settings-sleep',
          'settings-wave',
          'settings-download-quality',
          'settings-downloads',
          'settings-sort',
          'settings-export',
          'settings-import',
          'settings-token',
          'settings-licenses',
        ]) {
          if (find.byKey(Key(key)).evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              find.byKey(Key(key)),
              220,
              scrollable: find.descendant(
                of: find.byKey(const Key('settings-list')),
                matching: find.byType(Scrollable),
              ),
            );
          }
          await tester.ensureVisible(find.byKey(Key(key)));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull, reason: key);
        }
        await screenshot('v111-03-settings-large-text');
        await tester.drag(
          find.byKey(const Key('settings-list')),
          const Offset(0, 2400),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tap(find.byKey(const Key('settings-stream-quality')));
        expect(find.byType(SettingsRow), findsWidgets);
        await screenshot('v111-04-quality-large-text');
        await tap(find.byKey(const Key('quality-high')));
        await until(
          () => music.audioPreferences.streaming == AudioQuality.high,
        );
        expect(music.audioPreferences.downloads, AudioQuality.economy);
        expect(tester.takeException(), isNull);
        print(
          'SETTINGS UI: independent qualities, uninterrupted audio, next source, downloads, repeat/timer/sort, account isolation, persistence and large text passed',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        app.dispose();
        await music.disposeHandler();
        api.close();
        await server.close(force: true);
        await store.db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

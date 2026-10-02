// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/playback/music_handler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native secure session survives controller restart', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final directory = await Directory.systemTemp.createTemp('zvuk-auth-test');
    final store = await LibraryStore.open(
      databasePath: '${directory.path}/test.db',
    );
    final music = await AudioService.init<MusicHandler>(
      builder: () => MusicHandler(store),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.oleg.zvuk_personal.test',
        androidNotificationChannelName: 'Проверка входа',
        androidNotificationIcon: 'drawable/ic_stat_music',
      ),
    );
    await music.initialize();
    final app = AppController(store, music);
    AppController? restored;
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:18746/credential'),
      );
      final token = jsonDecode(response.body)['token'] as String;
      await app.connect(token);
      expect(app.account, isNotNull);
      expect(app.tracks, isNotEmpty);
      expect(app.message, isNull);
      final session = await app.tokens.read();
      expect(session, isNotNull);
      // Boolean comparison ensures a failing assertion cannot print a token.
      expect(session!.token == token, isTrue);
      expect(session.account.id, app.account!.id);
      restored = AppController(store, music);
      await restored.initialize();
      expect(restored.account!.id, app.account!.id);
      expect(restored.tracks.length, app.tracks.length);
      expect(restored.api, isNotNull);
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (restored.busy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(restored.busy, isFalse);
      expect(restored.message, isNull);
      print(
        'SECURE_SESSION login=passed restore=passed favorites=${restored.tracks.length}',
      );
    } finally {
      await const FlutterSecureStorage().delete(key: 'zvuk_session');
      restored?.api?.close();
      app.api?.close();
      restored?.dispose();
      app.dispose();
      await music.disposeHandler();
      await store.close();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

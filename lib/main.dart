import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'data/library_store.dart';
import 'playback/music_handler.dart';
import 'playback/service_config.dart';
import 'ui/app.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'zvuk-music — описание протокола',
    ], await rootBundle.loadString('THIRD_PARTY_NOTICES.txt'));
  });
  try {
    final store = await LibraryStore.open();
    final music = await AudioService.init<MusicHandler>(
      builder: () => MusicHandler(store),
      config: musicServiceConfig,
    );
    await music.initialize();
    final app = AppController(store, music);
    await app.initialize();
    runApp(ZvukApp(app));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: appTheme(),
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Не удалось открыть приложение. Закрой его и открой снова. Сохранённые оценки остаются на телефоне.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

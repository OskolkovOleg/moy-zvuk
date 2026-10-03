// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/data/wave_options.dart';
import 'package:zvuk_personal/data/wave_source.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test('Live tuner options read only', () async {
    final credential = await http.get(
      Uri.parse('http://127.0.0.1:18746/credential'),
    );
    final api = ZvukApi(jsonDecode(credential.body)['token'] as String);
    try {
      for (final options in [
        const WaveOptions(mood: WaveMood.energetic),
        const WaveOptions(
          language: WaveLanguage.russian,
          genres: ['rock'],
          popularity: WavePopularity.hits,
        ),
        const WaveOptions(
          mood: WaveMood.calm,
          language: WaveLanguage.foreign,
          popularity: WavePopularity.discoveries,
        ),
      ]) {
        final page = await api.recommendations(
          const WaveSource.personal(),
          count: 3,
          options: options,
        );
        expect(page.tracks, isNotEmpty);
        expect(
          page.tracks.every((t) => t.id.isNotEmpty && t.duration > 0),
          true,
        );
        print('LIVE TUNER ${options.summary}: returned tracks (read-only)');
      }
    } finally {
      api.close();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

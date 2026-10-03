// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/data/wave_source.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test('Live contextual recommendations read only', () async {
    final credential = await http.get(
      Uri.parse('http://127.0.0.1:18746/credential'),
    );
    final api = ZvukApi(jsonDecode(credential.body)['token'] as String);
    try {
      final sources = [
        const WaveSource(kind: WaveKind.track, id: '177981965', title: 'Track'),
        const WaveSource(
          kind: WaveKind.artist,
          id: '213251995',
          title: 'Artist',
        ),
        const WaveSource(kind: WaveKind.album, id: '49910875', title: 'Album'),
        const WaveSource(
          kind: WaveKind.playlist,
          id: '1062105',
          title: 'Playlist',
        ),
        const WaveSource.favorites(),
      ];
      for (final source in sources) {
        final page = await api.recommendations(source, count: 3);
        expect(page.tracks, isNotEmpty, reason: source.kind.name);
        expect(
          page.tracks.every((t) => t.id.isNotEmpty && t.duration > 0),
          true,
        );
        final more = await api.recommendations(
          source,
          count: 3,
          cursor: page.cursor,
        );
        expect(more.tracks, isNotEmpty, reason: source.kind.name);
        print(
          'LIVE RADIO ${source.kind.name}: two batches, passed (read-only)',
        );
      }
    } finally {
      api.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

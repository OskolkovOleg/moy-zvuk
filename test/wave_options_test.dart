import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/wave_options.dart';
import 'package:zvuk_personal/data/wave_source.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';

void main() {
  test('Options restore defaults and sanitize corrupt/obsolete values', () {
    for (final j in [
      null,
      [],
      {'mood': 'unknown', 'genres': 42},
    ]) {
      expect(WaveOptions.fromJson(j).isDefault, true);
    }
    final options = WaveOptions.fromJson({
      'mood': 'energetic',
      'language': 'russian',
      'popularity': 'hits',
      'genres': ['rock', 'rock', 'unsupported', 42, 'pop'],
    });
    expect(options.genres, ['rock', 'pop']);
    expect(WaveOptions.fromJson(options.toJson()).toApi(), {
      'mood': 'energy:1,fun:0.5',
      'language': 'russian',
      'popular': 1,
      'genre': [
        {'name': 'rock'},
        {'name': 'pop'},
      ],
    });
    expect(options.summary, contains('Хиты'));
  });
  test(
    'Only personal wave receives filters; default remains unfiltered',
    () async {
      final requests = <Map<String, dynamic>>[];
      final api = ZvukApi(
        'fixture',
        client: MockClient((r) async {
          requests.add(jsonDecode(r.body));
          return http.Response('{"data":{"personalWaveContent":[]}}', 200);
        }),
      );
      const options = WaveOptions(
        language: WaveLanguage.foreign,
        popularity: WavePopularity.discoveries,
      );
      try {
        await api.recommendations(
          const WaveSource.personal(),
          options: options,
        );
        await api.recommendations(
          const WaveSource.favorites(),
          options: options,
        );
        await api.recommendations(
          const WaveSource(kind: WaveKind.playlist, id: '42', title: 'List'),
          options: options,
        );
        await api.recommendations(const WaveSource.personal());
        expect(requests.first['variables']['options'], {
          'language': 'foreign',
          'popular': 0,
        });
        expect(
          requests.skip(1).every((r) => !r['variables'].containsKey('options')),
          true,
        );
      } finally {
        api.close();
      }
    },
  );
  test('Artist names with commas stay aligned with IDs through cache', () {
    final track = Track.fromApi({
      'id': '1',
      'artists': [
        {'id': '2', 'title': 'Tyler, The Creator'},
        {'id': '3', 'title': 'Guest'},
      ],
    });
    final restored = Track.fromJson(track.toJson());
    expect(restored.artistNames, ['Tyler, The Creator', 'Guest']);
    expect(restored.artistIds, ['2', '3']);
    expect(Track.fromJson({'id': 'old', 'title': 'Old'}).artistNames, isEmpty);
  });
}

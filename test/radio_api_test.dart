import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/catalog_models.dart';
import 'package:zvuk_personal/data/wave_source.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';

void main() {
  test(
    'Source round trips; corrupt source cannot silently become personal',
    () {
      for (final kind in CatalogKind.values) {
        final source = WaveSource.fromCatalog(
          CatalogItem(id: '42', title: 'Test', kind: kind),
        );
        expect(WaveSource.fromJson(source.toJson()).toJson(), source.toJson());
      }
      expect(
        WaveSource.fromTrack(const Track(id: '1', title: 'Song')).queueTitle,
        'Поток · Song',
      );
      for (final j in [
        <String, dynamic>{},
        {'kind': 'unknown'},
        {'kind': 'playlist', 'id': 'bad', 'title': 'Test'},
        {'kind': 'track', 'id': '', 'title': 'Test'},
      ]) {
        expect(() => WaveSource.fromJson(j), throwsA(isA<Exception>()));
      }
    },
  );
  test(
    'Context radio uses confirmed enums and keeps a repeating cursor',
    () async {
      for (final kind in [WaveKind.track, WaveKind.artist, WaveKind.album]) {
        final api = ZvukApi(
          'fixture',
          client: MockClient((req) async {
            final b = jsonDecode(req.body), v = b['variables'];
            expect(v, {
              'id': '42',
              'type': switch (kind) {
                WaveKind.track => 'TRACK',
                WaveKind.artist => 'ARTIST',
                _ => 'RELEASE',
              },
              'first': 15,
              'cursor': 15,
            });
            return http.Response(
              jsonEncode({
                'data': {
                  'recommenderRadio': {
                    'cursor': 15,
                    'tracks': [
                      null,
                      {},
                      {'id': '9', 'title': 'Result'},
                    ],
                  },
                },
              }),
              200,
            );
          }),
        );
        final p = await api.recommendations(
          WaveSource(kind: kind, id: '42', title: 'Test'),
          cursor: 15,
        );
        expect(p.tracks.single.id, '9');
        expect(p.cursor, 15);
        api.close();
      }
    },
  );
  test('Personal favorites and playlist flows use the wave endpoint', () async {
    for (final source in [
      const WaveSource.personal(),
      const WaveSource.favorites(),
      const WaveSource(kind: WaveKind.playlist, id: '42', title: 'List'),
    ]) {
      final api = ZvukApi(
        'fixture',
        client: MockClient((req) async {
          final b = jsonDecode(req.body), v = b['variables'];
          expect(b['operationName'], 'getPersonalWave');
          expect(v['first'], 3);
          expect(v['waveInput'], switch (source.kind) {
            WaveKind.favorites => {'waveType': 'FAVTRACKS'},
            WaveKind.playlist => {'waveType': 'PLAYLIST', 'waveId': 42},
            _ => null,
          });
          return http.Response(
            '{"data":{"personalWaveContent":[null,{"id":"9","title":"Result"}]}}',
            200,
          );
        }),
      );
      expect(
        (await api.recommendations(source, count: 3)).tracks.single.id,
        '9',
      );
      api.close();
    }
  });
  test(
    'Empty radio is valid; malformed response and invalid paging fail',
    () async {
      const s = WaveSource(kind: WaveKind.track, id: '1', title: 'Song');
      for (final result in [
        {'tracks': [], 'cursor': 0},
        {},
        null,
      ]) {
        final api = ZvukApi(
          'fixture',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'data': {'recommenderRadio': result},
              }),
              200,
            ),
          ),
        );
        if (result is Map && result.containsKey('tracks')) {
          expect((await api.recommendations(s)).tracks, isEmpty);
        } else {
          await expectLater(
            api.recommendations(s),
            throwsA(isA<ZvukException>()),
          );
        }
        await expectLater(
          api.recommendations(s, count: 0),
          throwsArgumentError,
        );
        await expectLater(
          api.recommendations(s, cursor: -1),
          throwsArgumentError,
        );
        api.close();
      }
    },
  );
}

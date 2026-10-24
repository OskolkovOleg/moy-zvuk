import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zvuk_personal/data/catalog_models.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';

void main() {
  Map<String, dynamic> track(String id, {bool direct = true}) => {
    'id': id,
    'title': 'Track $id',
    'genres': direct
        ? [
            {'id': '39', 'name': 'Hip-Hop', 'shortName': ''},
          ]
        : [],
    'release': {
      'id': 'release-$id',
      'genres': [
        {'id': '23', 'name': 'Rock', 'shortName': ''},
      ],
    },
  };

  test(
    'Track hydration requests both genre sources and keeps requested order',
    () async {
      var calls = 0;
      final api = ZvukApi(
        'fixture',
        client: MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body);
          expect(body['operationName'], 'getTracks');
          expect(body['variables']['ids'], ['release', 'direct', 'missing']);
          expect(
            RegExp(r'genres\s*\{\s*id\s+name\s+shortName\s*\}')
                .allMatches(body['query'] as String),
            hasLength(2),
          );
          return http.Response(
            jsonEncode({
              'data': {
                'getTracks': [track('direct'), track('release', direct: false)],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final result = await api.tracks(['release', 'direct', 'missing']);
      expect(calls, 1);
      expect(result.map((t) => t.id), ['release', 'direct', 'missing']);
      expect(result[0].genreSource, GenreSource.release);
      expect(result[0].genres.single.name, 'Rock');
      expect(result[1].genreSource, GenreSource.track);
      expect(result[1].genres.single.name, 'Hip-Hop');
      expect(result[2].genres, isEmpty);
      expect(result[2].genreSource, isNull);
    },
  );

  test(
    'Catalog album tracks preserve per-track genres and release fallback',
    () async {
      final api = ZvukApi(
        'fixture',
        client: MockClient((request) async {
          final body = jsonDecode(request.body);
          expect(body['operationName'], 'catalogDetail');
          expect(body['query'], contains('genres { id name shortName }'));
          return http.Response(
            jsonEncode({
              'data': {
                'getReleases': [
                  {
                    'id': 'album',
                    'title': 'Album',
                    'tracks': [
                      track('direct'),
                      track('release', direct: false),
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final detail = await api.catalogDetail(
        const CatalogItem(id: 'album', title: 'Album', kind: CatalogKind.album),
      );
      expect(detail.tracks.map((t) => t.genreSource), [
        GenreSource.track,
        GenreSource.release,
      ]);
    },
  );
}

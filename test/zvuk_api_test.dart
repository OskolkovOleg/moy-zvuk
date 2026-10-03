import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/data/audio_preferences.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  test(
    'Streaming sends the selected quality only to the authenticated API',
    () async {
      final qualities = <String?>[];
      final api = ZvukApi(
        'test-secret',
        client: MockClient((request) async {
          expect(request.url.host, 'zvuk.com');
          expect(request.url.scheme, 'https');
          expect(request.headers['X-Auth-Token'], 'test-secret');
          qualities.add(request.url.queryParameters['quality']);
          return http.Response(
            '{"result":{"stream":"https://audio.example/track.mp3"}}',
            200,
          );
        }),
      );
      await api.streamUrl('one');
      await api.streamUrl('one', quality: AudioQuality.economy);
      expect(qualities, ['high', 'mid']);
      api.close();
    },
  );
  Map<String, dynamic> track(int i) => {
    'id': '$i',
    'title': 'Track $i',
    'artists': [
      {'title': 'Artist'},
    ],
    'duration': 180,
  };
  test('Playlist loads every page and does not forward credentials', () async {
    final offsets = <int>[];
    final api = ZvukApi(
      'test-secret',
      client: MockClient((req) async {
        expect(req.url.host, 'zvuk.com');
        expect(req.followRedirects, false);
        final offset = jsonDecode(req.body)['variables']['offset'] as int;
        offsets.add(offset);
        return http.Response(
          jsonEncode({
            'data': {
              'playlistTracks': List.generate(
                offset == 0 ? 100 : 1,
                (i) => track(offset + i),
              ),
            },
          }),
          200,
        );
      }),
    );
    expect(await api.playlistTracks('1'), hasLength(101));
    expect(offsets, [0, 100]);
    api.close();
  });
  test('Favorite hydration preserves source order and missing IDs', () async {
    final api = ZvukApi(
      'test',
      client: MockClient((req) async {
        final name = jsonDecode(req.body)['operationName'];
        return http.Response(
          jsonEncode({
            'data': name == 'userCollection'
                ? {
                    'collection': {
                      'tracks': [
                        {'id': '3'},
                        {'id': '1'},
                        {'id': '2'},
                      ],
                    },
                  }
                : {
                    'getTracks': [track(1), track(3)],
                  },
          }),
          200,
        );
      }),
    );
    final result = await api.favorites();
    expect(result.map((t) => t.id), ['3', '1', '2']);
    expect(result.last.title, 'Недоступный трек');
    api.close();
  });
  test(
    'Profile rejects anonymous account and redacts upstream failure',
    () async {
      final api = ZvukApi(
        'secret',
        client: MockClient(
          (_) async =>
              http.Response('{"result":{"id":123,"is_anonymous":true}}', 200),
        ),
      );
      await expectLater(
        api.profile(),
        throwsA(isA<ZvukException>().having((e) => e.auth, 'auth', true)),
      );
      api.close();
      final broken = ZvukApi(
        'secret',
        client: MockClient((_) async => http.Response('secret response', 403)),
      );
      await expectLater(
        broken.profile(),
        throwsA(
          isA<ZvukException>().having(
            (e) => e.message,
            'redacted',
            isNot(contains('secret')),
          ),
        ),
      );
      broken.close();
    },
  );
  test('Registered profile can omit the anonymous flag', () async {
    final api = ZvukApi(
      'test',
      client: MockClient(
        (_) async => http.Response(
          '{"result":{"id":12,"name":"Oleg","is_registered":true}}',
          200,
        ),
      ),
    );
    expect((await api.profile()).id, '12');
    api.close();
  });
  test('CamelCase API data and missing image', () {
    final t = Track.fromApi(track(1));
    expect(t.artists, 'Artist');
    expect(t.imageUrl, isNull);
    expect(
      artwork('/static/cover.jpg'),
      'https://zvuk.com/static/cover.jpg?size=600x600',
    );
  });
  test(
    'Same-origin routing redirect carries cookie; external redirect is blocked',
    () async {
      var calls = 0;
      final api = ZvukApi(
        'test',
        client: MockClient((req) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              '',
              307,
              headers: {
                'location': 'https://zvuk.com/api/tiny/profile',
                'set-cookie': 'route=one; Path=/; Secure; HttpOnly',
              },
            );
          }
          expect(req.headers['Cookie'], 'route=one');
          return http.Response(
            '{"result":{"id":12,"is_registered":true}}',
            200,
          );
        }),
      );
      expect((await api.profile()).id, '12');
      expect(calls, 2);
      api.close();
      calls = 0;
      final external = ZvukApi(
        'test',
        client: MockClient((req) async {
          calls++;
          return http.Response(
            '',
            307,
            headers: {'location': 'https://example.com/api/profile'},
          );
        }),
      );
      await expectLater(external.profile(), throwsA(isA<ZvukException>()));
      expect(calls, 1);
      external.close();
    },
  );
  test(
    'Search uses the opaque next-page cursor, not the numeric offset',
    () async {
      var calls = 0;
      final api = ZvukApi(
        'test',
        client: MockClient((req) async {
          calls++;
          final cursor = jsonDecode(req.body)['variables']['cursor'];
          expect(cursor, calls == 1 ? null : 'opaque-next-page');
          return http.Response(
            jsonEncode({
              'data': {
                'search': {
                  'tracks': {
                    'items': [track(calls)],
                    'page': {
                      'next': calls == 1 ? 30 : null,
                      'cursor': 'opaque-next-page',
                    },
                  },
                },
              },
            }),
            200,
          );
        }),
      );
      final first = await api.search('Song');
      expect(first.next, 'opaque-next-page');
      final second = await api.search('Song', cursor: first.next);
      expect(second.next, isNull);
      api.close();
    },
  );
}

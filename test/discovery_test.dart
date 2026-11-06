import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/discovery_models.dart';
import 'package:zvuk_personal/data/models.dart';

Track song(String id, {String? canonical, String? artist, bool? explicit}) =>
    Track(
      id: id,
      title: id,
      canonicalTrackId: canonical,
      artistIds: artist == null ? [] : [artist],
      explicit: explicit,
    );
DiscoveryCandidate pick(Track t, [String reason = 'source']) =>
    DiscoveryCandidate(t, reason);

void main() {
  test('Canonical identity survives API and cache; missing is unknown', () {
    final track = Track.fromApi({
      'id': 12,
      'title': 'Fixture',
      'canonicalTrackId': 10,
    });
    expect(track.canonicalTrackId, '10');
    expect(Track.fromJson(track.toJson()).canonicalTrackId, '10');
    expect(
      Track.fromJson({'id': 'old', 'title': 'Old'}).canonicalTrackId,
      null,
    );
  });
  test('Selection excludes library IDs, canonical versions, blocks and recent offers', () {
    final pools = [
      [
        pick(song('a')),
        pick(song('other', canonical: 'master')),
        pick(song('blocked')),
        pick(song('recent')),
        pick(song('fresh')),
        pick(song('another', canonical: 'fresh')),
      ],
    ];
    final found = selectDiscoveries(
      pools,
      library: [
        song('a'),
        song('old-version', canonical: 'master'),
      ],
      excluded: {'blocked', 'recent'},
    );
    expect(found.map((c) => c.track.id), ['fresh']);
  });
  test(
    'Sources interleave and artist cap prevents a single artist dominating',
    () {
      final found = selectDiscoveries(
        [
          List.generate(10, (i) => pick(song('a$i', artist: 'a'), 'one')),
          List.generate(10, (i) => pick(song('b$i', artist: 'b$i'), 'two')),
        ],
        artistLimit: 2,
        limit: 6,
      );
      expect(found.map((c) => c.track.id), [
        'a0',
        'b0',
        'a1',
        'b1',
        'b2',
        'b3',
      ]);
      expect(found.take(2).map((c) => c.reason), ['one', 'two']);
    },
  );
  test('Censored discovery accepts only explicit false', () {
    expect(
      selectDiscoveries([
        [
          pick(song('yes', explicit: false)),
          pick(song('no', explicit: true)),
          pick(song('unknown')),
        ],
      ], censoredOnly: true).map((c) => c.track.id),
      ['yes'],
    );
  });
  test('Seeds use scores, distinct artists, rotate, and never use low-scored favorites', () {
    final library = [
      song('a', artist: 'a'),
      song('b', artist: 'a'),
      song('c', artist: 'c'),
      song('d', artist: 'd'),
      song('e', artist: 'e'),
    ];
    const ratings = {
      'a': Rating(15, 6),
      'b': Rating(14, 5),
      'c': Rating(12, 3),
      'd': Rating(8, 1),
    };
    expect(discoverySeeds(library, ratings, limit: 3).map((t) => t.id), [
      'a',
      'c',
      'e',
    ]);
    expect(
      discoverySeeds(library, ratings, offset: 1, limit: 1).single.id,
      'c',
    );
  });
  test('Releases require real recent dates; no undated or future fallback', () {
    final now = DateTime.utc(2026, 11, 6);
    expect(isRecentRelease(DateTime.utc(2026, 10, 30), now), true);
    expect(isRecentRelease(null, now), false);
    expect(isRecentRelease(DateTime.utc(2026, 11, 7), now), false);
    expect(isRecentRelease(DateTime.utc(2026, 1, 1), now), false);
  });
}

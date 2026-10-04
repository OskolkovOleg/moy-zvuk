import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/personal_models.dart';

void main() {
  test(
    'LRC repeat timestamps, fractions, offset and active-line boundaries',
    () {
      final lyrics = SongLyrics.parse(
        '[ar:Fixture]\n[offset:-50]\n[00:02.5][00:01.25]Example\n[00:03.001]Next\n[00:04.00]',
      );
      expect(lyrics.synced, true);
      expect(lyrics.lines.map((l) => l.at!.inMilliseconds), [
        1200,
        2450,
        2951,
        3950,
      ]);
      expect(lyrics.activeLine(const Duration(milliseconds: 1199)), -1);
      expect(lyrics.activeLine(const Duration(milliseconds: 1200)), 0);
      expect(lyrics.activeLine(const Duration(milliseconds: 3000)), 2);
      expect(lyrics.activeLine(const Duration(hours: 1)), 3);
    },
  );
  test('Plain text keeps stanzas; no fake synchronization', () {
    final lyrics = SongLyrics.parse(
      '\nFirst\n\nSecond\n',
      translation: 'Translation',
    );
    expect(lyrics.synced, false);
    expect(lyrics.lines.map((l) => l.text), ['First', '', 'Second']);
    expect(lyrics.activeLine(Duration.zero), -1);
    expect(lyrics.translation, 'Translation');
    expect(SongLyrics.parse(' ').lines, isEmpty);
  });
  test('Cached lyrics preserve timing, translation and stanza boundaries', () {
    final timed = SongLyrics.parse(
      '[00:01.5]First\n[00:10]Second',
      translation: 'Первая\nВторая',
    );
    final cached = SongLyrics.fromJson(timed.toJson());
    expect(cached.lines.first.at, const Duration(milliseconds: 1500));
    expect(cached.activeLine(const Duration(seconds: 10)), 1);
    expect(cached.translation, timed.translation);
    final plain = SongLyrics.parse('First\n\nSecond');
    expect(SongLyrics.fromJson(plain.toJson()).lines.map((line) => line.text), [
      'First',
      '',
      'Second',
    ]);
    expect(
      () => SongLyrics.fromJson({
        'lines': [
          {'text': 'First', 'at': 'invalid'},
        ],
      }),
      throwsFormatException,
    );
  });
}

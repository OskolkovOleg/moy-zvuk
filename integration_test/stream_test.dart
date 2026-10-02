// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:zvuk_personal/data/zvuk_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Real Zvuk account and full MP3 streaming on Android', (
    tester,
  ) async {
    final client = http.Client();
    final credential = jsonDecode(
      (await client.get(Uri.parse('http://127.0.0.1:18746/credential'))).body,
    );
    final api = ZvukApi(credential['token']);
    final account = await api.profile();
    expect(account.id, isNotEmpty);
    final favorites = await api.favorites();
    final playlists = await api.playlists();
    final search = await api.search('SAYAN Мальборо');
    expect(favorites, isNotEmpty);
    expect(playlists, isNotEmpty);
    expect(search.tracks, isNotEmpty);
    if (search.next != null) {
      final second = await api.search('SAYAN Мальборо', cursor: search.next);
      expect(second.tracks, isNotEmpty);
      expect(second.tracks.first.id, isNot(search.tracks.first.id));
    }
    final playlist = await api.playlistTracks(playlists.first.id);
    expect(playlist, isNotEmpty);
    // Evidence contains counts only; never credentials or signed URLs.
    print(
      'LIVE_LIBRARY favorites=${favorites.length} playlists=${playlists.length} playlistTracks=${playlist.length} search=${search.tracks.length}',
    );
    final player = AudioPlayer();
    try {
      await player.setVolume(0);
      for (final id in ['177981965', '180082552']) {
        final url = await api.streamUrl(id);
        await player.setUrl(url);
        expect(player.duration!.inSeconds, greaterThan(60));
        unawaited(player.play());
        await player.positionStream
            .firstWhere((p) => p.inMilliseconds > 1000)
            .timeout(const Duration(seconds: 30));
        final duration = player.duration!;
        await player.seek(duration - const Duration(seconds: 2));
        await player.processingStateStream
            .firstWhere((s) => s == ProcessingState.completed)
            .timeout(const Duration(seconds: 30));
        print(
          'LIVE_AUDIO track=$id duration=${duration.inSeconds}s seek=passed completion=passed',
        );
        await player.pause();
      }
    } finally {
      await player.dispose();
      api.close();
      client.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

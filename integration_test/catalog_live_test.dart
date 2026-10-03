// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/data/catalog_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test('Live catalog reads and isolated scratch playlist lifecycle', () async {
    final response = await http.get(
      Uri.parse('http://127.0.0.1:18746/credential'),
    );
    final api = ZvukApi(jsonDecode(response.body)['token'] as String);
    String? scratch;
    try {
      final account = await api.profile();
      final charts = await api.chartPlaylists();
      expect(charts, hasLength(3));
      final personal = await api.personalPlaylists();
      expect(personal, isNotEmpty);
      final editorial = await api.editorialPlaylists();
      expect(editorial, isNotEmpty);
      final chart = await api.catalogDetail(CatalogItem.playlist(charts.first));
      expect(chart.tracks.length, greaterThan(50));
      final wave = await api.personalWave();
      expect(wave, isNotEmpty);
      for (final kind in CatalogKind.values) {
        final page = await api.searchCatalog('Billie Eilish', kind);
        expect(page.items.isNotEmpty || page.tracks.isNotEmpty, true);
        if (page.next != null) {
          final next = await api.searchCatalog(
            'Billie Eilish',
            kind,
            cursor: page.next,
          );
          // Upstream reports a next offset even for exhausted artist results.
          if (next.items.isEmpty && next.tracks.isEmpty) {
            expect(next.next, isNull);
          }
        }
        if (kind == CatalogKind.artist || kind == CatalogKind.album) {
          final detail = await api.catalogDetail(page.items.first);
          expect(detail.tracks, isNotEmpty);
        }
      }
      final ids = chart.tracks.take(2).map((t) => t.id).toList();
      scratch = await api.createPlaylist(
        'Мой Звук — временная проверка',
        trackIds: ids.take(1).toList(),
      );
      expect(scratch.isNotEmpty, true);
      var p = (await api.getPlaylists([scratch])).single;
      expect(p.ownerId == account.id, true);
      expect(p.isPublic, false);
      await api.renamePlaylist(scratch, 'Мой Звук — временная проверка 2');
      await api.addPlaylistTracks(scratch, ids.skip(1).toList());
      expect(
        (await api.playlistTracks(scratch)).map((t) => t.id),
        unorderedEquals(ids),
      );
      p = (await api.getPlaylists([scratch])).single;
      expect(p.title, 'Мой Звук — временная проверка 2');
      await api.replacePlaylistTracks(p, ids);
      expect((await api.playlistTracks(scratch)).map((t) => t.id), ids);
      await api.replacePlaylistTracks(p, ids.skip(1).toList());
      expect((await api.playlistTracks(scratch)).map((t) => t.id), ids.skip(1));
      // Collection mutations touch only this disposable playlist.
      await api.setCollectionItem(scratch, liked: false, playlist: true);
      await api.setCollectionItem(scratch, liked: true, playlist: true);
      expect((await api.playlists()).any((p) => p.id == scratch), true);
      print(
        'LIVE catalog four categories + paging + artist/album + charts + personal/editorial + wave: passed',
      );
      print('SCRATCH create, owner, rename, add, replace, collection: passed');
    } finally {
      if (scratch != null) {
        await api.deletePlaylist(scratch);
        print('SCRATCH cleanup: passed');
      }
      api.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

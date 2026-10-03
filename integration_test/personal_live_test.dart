// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';
import 'package:zvuk_personal/data/catalog_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Live saved catalog, paginated history and timed lyrics (read only)',
    () async {
      final credential = await http.get(
        Uri.parse('http://127.0.0.1:18746/credential'),
      );
      final api = ZvukApi(jsonDecode(credential.body)['token'] as String);
      try {
        final saved = await api.savedCatalog();
        expect(saved.where((i) => i.kind == CatalogKind.album), isNotEmpty);
        expect(saved.where((i) => i.kind == CatalogKind.artist), isNotEmpty);
        final history = await api.listeningHistory(limit: 3);
        expect(history.entries, isNotEmpty);
        expect(history.nextOffset, 3);
        final more = await api.listeningHistory(
          offset: history.nextOffset!,
          limit: 3,
        );
        expect(more.entries, isNotEmpty);
        final lyrics = await api.lyrics('5896627');
        expect(lyrics, isNotNull);
        expect(lyrics!.synced, true);
        expect(lyrics.lines.length, greaterThan(10));
        print(
          'LIVE saved artists/albums, history paging, lyrics parsing: passed (read-only)',
        );
      } finally {
        api.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

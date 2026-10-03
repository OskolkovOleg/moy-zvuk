// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:zvuk_personal/data/catalog_models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test('Live quick search and category pagination, read only', () async {
    final credential = await http.get(
      Uri.parse('http://127.0.0.1:18746/credential'),
    );
    final api = ZvukApi(jsonDecode(credential.body)['token'] as String);
    try {
      for (final query in ['Билли', 'Мальборо']) {
        final hits = await api.quickSearch(query);
        expect(hits, isNotEmpty);
        expect(hits.every((h) => h.key.isNotEmpty), true);
      }
      final page = await api.searchCatalog('любовь', CatalogKind.track);
      expect(page.tracks, isNotEmpty);
      expect(page.next, isNotNull);
      final more = await api.searchCatalog(
        'любовь',
        CatalogKind.track,
        cursor: page.next,
      );
      expect(more.tracks, isNotEmpty);
      print(
        'LIVE SEARCH: quick mixed music and full track pagination passed (read-only)',
      );
    } finally {
      api.close();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

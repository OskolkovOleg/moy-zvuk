import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:zvuk_personal/app_controller.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/history_store.dart';
import 'package:zvuk_personal/data/models.dart';
import 'package:zvuk_personal/data/catalog_models.dart';
import 'package:zvuk_personal/data/zvuk_api.dart';

import 'collection_controller_test.dart' show UnusedMusic;

void main() {
  sqfliteFfiInit();
  late LibraryStore store;
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zvuk-personal-test');
    store = await LibraryStore.open(
      factory: Platform.isAndroid ? native.databaseFactory : databaseFactoryFfi,
      databasePath: '${directory.path}/test.db',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  test('History transactions preserve concurrent starts, isolate accounts and cap 200', () async {
    final history = HistoryStore(store), now = DateTime.now();
    await Future.wait(
      List.generate(
        205,
        (i) => history.record(
          'a',
          Track(id: '$i', title: 'Fixture'),
          now.add(Duration(seconds: i)),
        ),
      ),
    );
    var rows = await history.recent('a');
    expect(rows.length, 200);
    expect(rows.first.track.id, '204');
    expect(await history.recent('b'), isEmpty);
    await history.record(
      'a',
      const Track(id: '20', title: 'Again'),
      now.add(const Duration(hours: 1)),
    );
    rows = await history.recent('a');
    expect(rows.length, 200);
    expect(rows.first.track.title, 'Again');
    expect(rows.where((r) => r.track.id == '20').length, 1);
  });
  http.Response response(Object value) =>
      http.Response(jsonEncode({'data': value}), 200);
  test('Slow saved collection refresh cannot overwrite a new like', () async {
    final delayed = Completer<http.Response>();
    final app = AppController(store, UnusedMusic())
      ..account = const Account('a', 'Fixture')
      ..savedCatalogKnown = true;
    app.api = ZvukApi(
      'fixture',
      client: MockClient((req) async {
        final b = jsonDecode(req.body);
        if (b['operationName'] == 'savedCatalog') return delayed.future;
        return response({
          'collection': {'addItem': null},
        });
      }),
    );
    final refresh = app.refreshSavedCatalog();
    const item = CatalogItem(id: 'r', title: 'Album', kind: CatalogKind.album);
    await app.saveCatalogItem(item, true);
    delayed.complete(
      response({
        'collection': {'artists': [], 'releases': []},
      }),
    );
    await refresh;
    expect(app.hasCatalogItem(item), true);
    expect((await store.get('a', 'saved-catalog') as List).length, 1);
    expect(app.savedCatalogLoading, false);
    app.api!.close();
    app.dispose();
  });
  test('Old session refresh cannot populate another account', () async {
    final delayed = Completer<http.Response>();
    final api = ZvukApi('fixture', client: MockClient((_) => delayed.future));
    final app = AppController(store, UnusedMusic())
      ..account = const Account('a', 'A')
      ..api = api;
    final pending = app.refreshSavedCatalog();
    app.account = const Account('b', 'B');
    app.api = null;
    delayed.complete(
      response({
        'collection': {'artists': [], 'releases': []},
      }),
    );
    await pending;
    expect(app.savedCatalogKnown, false);
    expect(await store.get('b', 'saved-catalog'), isNull);
    api.close();
    app.dispose();
  });
}

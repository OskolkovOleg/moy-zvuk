import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/rating_store_test.dart' as ratings;
import '../test/playback_queue_test.dart' as queue;
import '../test/zvuk_api_test.dart' as api;
import '../test/shuffle_test.dart' as shuffle;
import '../test/rating_position_test.dart' as positions;

import '../test/catalog_api_test.dart' as catalog;
import '../test/collection_controller_test.dart' as collection;
import '../test/wave_buffer_test.dart' as wave;

import '../test/lyrics_test.dart' as lyrics;
import '../test/personal_api_test.dart' as personal;
import '../test/personal_store_test.dart' as personal_store;

import '../test/sleep_timer_test.dart' as sleep;
import '../test/radio_api_test.dart' as radio;
import '../test/search_test.dart' as search;
import '../test/wave_options_test.dart' as wave_options;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Android SQLite ratings', ratings.main);
  group('Queue', queue.main);
  group('Radio API', radio.main);
  group('Wave options', wave_options.main);
  group('Search', search.main);
  group('Sleep timer', sleep.main);
  group('Lyrics', lyrics.main);
  group('Personal API', personal.main);
  group('Personal store', personal_store.main);
  group('Catalog', catalog.main);
  group('Collection edits', collection.main);
  group('Wave buffer', wave.main);
  group('API', api.main);
  group('Shuffle', shuffle.main);
  group('Rating positions', positions.main);
}

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Android SQLite ratings', ratings.main);
  group('Queue', queue.main);
  group('Catalog', catalog.main);
  group('Collection edits', collection.main);
  group('Wave buffer', wave.main);
  group('API', api.main);
  group('Shuffle', shuffle.main);
  group('Rating positions', positions.main);
}

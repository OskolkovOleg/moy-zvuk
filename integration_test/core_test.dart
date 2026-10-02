import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/rating_store_test.dart' as ratings;
import '../test/playback_queue_test.dart' as queue;
import '../test/zvuk_api_test.dart' as api;
import '../test/shuffle_test.dart' as shuffle;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Android SQLite ratings', ratings.main);
  group('Queue', queue.main);
  group('API', api.main);
  group('Shuffle', shuffle.main);
}

import 'package:integration_test/integration_test.dart';

import '../test/widget_test.dart' as widgets;
import '../test/library_voting_widget_test.dart' as library_widgets;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  widgets.main();
  library_widgets.main();
}

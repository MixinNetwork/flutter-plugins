import 'dart:io';

import 'package:integration_test/integration_test.dart';

import 'src/android_drop_scenarios.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    registerAndroidDropTests();
  } else {
    throw UnsupportedError(
      'No integration scenarios for ${Platform.operatingSystem}',
    );
  }
}

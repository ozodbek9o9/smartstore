import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_store/services/local_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'persists explicit logout until the user successfully signs in',
    () async {
      SharedPreferences.setMockInitialValues({});

      expect(await LocalSessionService.isLoggedOut(), isFalse);

      await LocalSessionService.markLoggedOut();
      expect(await LocalSessionService.isLoggedOut(), isTrue);

      await LocalSessionService.clearLoggedOut();
      expect(await LocalSessionService.isLoggedOut(), isFalse);
    },
  );
}

import 'package:shared_preferences/shared_preferences.dart';

class LocalSessionService {
  LocalSessionService._();

  static const _loggedOutKey = 'smartstore_explicitly_logged_out';

  static Future<bool> isLoggedOut() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_loggedOutKey) ?? false;
  }

  static Future<void> markLoggedOut() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_loggedOutKey, true);
  }

  static Future<void> clearLoggedOut() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_loggedOutKey);
  }
}

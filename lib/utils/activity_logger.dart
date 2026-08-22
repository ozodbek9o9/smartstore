import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'tenant_firestore.dart';

class ActivityLogger {
  static Future<void> log({
    required String username,
    required String type, // 'login_success', 'login_failed', 'logout'
    required String result, // 'success', 'failed'
  }) async {
    try {
      String ipAddress = 'Unknown';
      try {
        final response = await http
            .get(Uri.parse('https://api.ipify.org?format=json'))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          ipAddress = jsonDecode(response.body)['ip'];
        }
      } catch (_) {}

      String deviceName = 'Unknown Device';
      String browserApp = 'App';

      final deviceInfo = DeviceInfoPlugin();

      if (kIsWeb) {
        final webBrowserInfo = await deviceInfo.webBrowserInfo;
        deviceName = 'Web Browser';
        browserApp = webBrowserInfo.browserName.name.toUpperCase();
      } else {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceName = '${androidInfo.brand} ${androidInfo.model}';
          browserApp = 'Mobile App';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceName = '${iosInfo.name} ${iosInfo.systemVersion}';
          browserApp = 'Mobile App';
        } else if (Platform.isWindows) {
          await deviceInfo.windowsInfo;
          deviceName = 'Windows PC';
          browserApp = 'Desktop App';
        } else if (Platform.isMacOS) {
          final macInfo = await deviceInfo.macOsInfo;
          deviceName = macInfo.model;
          browserApp = 'Desktop App';
        }
      }

      await TenantFirestore.activityLogs.add({
        'timestamp': FieldValue.serverTimestamp(),
        'username': username,
        'type': type,
        'device': deviceName,
        'browser_app': browserApp,
        'ip_address': ipAddress,
        'result': result,
      });
    } catch (e) {
      debugPrint('Error logging activity: $e');
    }
  }
}

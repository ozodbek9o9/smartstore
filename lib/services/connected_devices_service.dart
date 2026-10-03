import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectedDevicesService {
  ConnectedDevicesService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static const defaultLimit = 1;
  static const minimumLimit = 1;
  static const maximumLimit = 10;
  static const _deviceIdPreference = 'smartstore_connected_device_id';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static bool canRegisterDevice({
    required int deviceCount,
    required int limit,
    required bool alreadyRegistered,
  }) => alreadyRegistered || deviceCount < limit;

  Future<String> getDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final existingId = preferences.getString(_deviceIdPreference);
    if (existingId != null && existingId.isNotEmpty) return existingId;

    final random = Random.secure();
    final generatedId = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await preferences.setString(_deviceIdPreference, generatedId);
    return generatedId;
  }

  Future<bool> registerDevice(
    DocumentReference<Map<String, dynamic>> accountReference,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('A signed-in user is required.');

    final deviceId = await getDeviceId();
    final now = Timestamp.now();
    final deviceName = _deviceName;
    final devicePlatform = Platform.operatingSystem;
    var registered = false;

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(accountReference);
      final account = snapshot.data() ?? const <String, dynamic>{};
      final devices = _readDevices(account['connectedDevices']);
      final existingDevice = devices[deviceId];
      final limit = _readLimit(account['deviceLimit']);
      if (!canRegisterDevice(
        deviceCount: devices.length,
        limit: limit,
        alreadyRegistered: existingDevice != null,
      )) {
        return;
      }

      devices[deviceId] = {
        'name': deviceName,
        'platform': devicePlatform,
        'firebaseUid': user.uid,
        'createdAt': existingDevice?['createdAt'] ?? now,
        'lastSeenAt': now,
      };
      final updates = <String, dynamic>{
        'deviceLimit': limit,
        'connectedDevices': devices,
      };
      if (accountReference.parent.id == 'users') updates['uid'] = user.uid;
      transaction.set(accountReference, updates, SetOptions(merge: true));
      registered = true;
    });
    return registered;
  }

  Future<bool> registerCurrentSession() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final profileReference = _firestore.collection('users').doc(user.uid);
    final profile = await profileReference.get();
    final customerId = profile.data()?['customerId']?.toString() ?? '';
    final accountReference = customerId.isEmpty
        ? profileReference
        : _firestore.collection('customers').doc(customerId);
    return registerDevice(accountReference);
  }

  Future<void> releaseCurrentDevice() async {
    if (_auth.currentUser == null) return;
    final accountReference = await _currentAccountReference();
    final deviceId = await getDeviceId();
    await removeDevice(accountReference, deviceId);
  }

  Future<void> removeDevice(
    DocumentReference<Map<String, dynamic>> accountReference,
    String deviceId,
  ) async {
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(accountReference);
      if (!snapshot.exists) return;
      final account = snapshot.data() ?? const <String, dynamic>{};
      final devices = _readDevices(account['connectedDevices']);
      if (devices.remove(deviceId) == null) return;
      transaction.update(accountReference, {'connectedDevices': devices});
    });
  }

  Future<void> setLimit(
    DocumentReference<Map<String, dynamic>> accountReference,
    int limit,
  ) async {
    if (limit < minimumLimit || limit > maximumLimit) {
      throw RangeError.range(limit, minimumLimit, maximumLimit, 'limit');
    }
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(accountReference);
      if (!snapshot.exists) throw StateError('Account data was not found.');
      transaction.update(accountReference, {'deviceLimit': limit});
    });
  }

  Future<DocumentReference<Map<String, dynamic>>>
  _currentAccountReference() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('A signed-in user is required.');
    final profileReference = _firestore.collection('users').doc(user.uid);
    final profile = await profileReference.get();
    final customerId = profile.data()?['customerId']?.toString() ?? '';
    return customerId.isEmpty
        ? profileReference
        : _firestore.collection('customers').doc(customerId);
  }

  static Map<String, Map<String, dynamic>> _readDevices(Object? value) {
    if (value is! Map) return <String, Map<String, dynamic>>{};
    return value.map((key, value) {
      final data = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
      return MapEntry(key.toString(), data);
    });
  }

  static int _readLimit(Object? value) {
    if (value is! num) return defaultLimit;
    return value.toInt().clamp(minimumLimit, maximumLimit);
  }

  static String get _deviceName {
    try {
      final hostname = Platform.localHostname.trim();
      if (hostname.isNotEmpty) return hostname;
    } catch (_) {}
    return '${Platform.operatingSystem} device';
  }
}

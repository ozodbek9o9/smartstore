import 'package:flutter_test/flutter_test.dart';
import 'package:smart_store/services/connected_devices_service.dart';

void main() {
  test('denies a new device when the configured capacity is full', () {
    expect(
      ConnectedDevicesService.canRegisterDevice(
        deviceCount: 1,
        limit: 1,
        alreadyRegistered: false,
      ),
      isFalse,
    );
  });

  test('allows a registered device to sign in again at capacity', () {
    expect(
      ConnectedDevicesService.canRegisterDevice(
        deviceCount: 1,
        limit: 1,
        alreadyRegistered: true,
      ),
      isTrue,
    );
  });

  test('allows another device when capacity remains', () {
    expect(
      ConnectedDevicesService.canRegisterDevice(
        deviceCount: 4,
        limit: 5,
        alreadyRegistered: false,
      ),
      isTrue,
    );
  });
}

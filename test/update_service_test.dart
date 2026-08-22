import 'package:flutter_test/flutter_test.dart';
import 'package:smart_store/models/update_info.dart';
import 'package:smart_store/services/update_service.dart';

void main() {
  test('compares semantic versions numerically', () {
    expect(UpdateService.compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(UpdateService.compareVersions('2.0.0', '2.9.9'), lessThan(0));
    expect(UpdateService.compareVersions('1.2.3+8', '1.2.3'), equals(0));
  });

  test('rejects insecure or malformed manifests', () {
    expect(
      () => UpdateInfo.fromJson({
        'version': '1.0.1',
        'downloadUrl': 'http://example.com/update.zip',
        'sha256': 'a' * 64,
      }),
      throwsFormatException,
    );
    expect(
      () => UpdateInfo.fromJson({
        'version': '1.0.1',
        'downloadUrl': 'https://example.com/update.zip',
        'sha256': 'not-a-hash',
      }),
      throwsFormatException,
    );
  });

  test('parses a valid update manifest', () {
    final info = UpdateInfo.fromJson({
      'version': '1.0.1',
      'downloadUrl': 'https://example.com/SmartStore-1.0.1.zip',
      'sha256': 'a' * 64,
      'releaseNotes': ['Bug fixes'],
      'mandatory': false,
      'sizeBytes': 123,
    });

    expect(info.version, '1.0.1');
    expect(info.releaseNotes, ['Bug fixes']);
    expect(info.sizeBytes, 123);
  });
}

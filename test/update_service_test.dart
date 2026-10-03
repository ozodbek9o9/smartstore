import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_store/models/update_info.dart';
import 'package:smart_store/services/update_service.dart';

const _owner = 'smartstore-test';
const _repository = 'desktop-client';
final _installerHash = List.filled(64, 'a').join();

Map<String, dynamic> _release({
  String tag = 'v1.1.0',
  bool draft = false,
  bool prerelease = false,
  String? installerUrl,
}) {
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  final releasePath =
      'https://github.com/$_owner/$_repository/releases/download/$tag';
  final assetName = 'SmartStore-Setup-$version.exe';
  return {
    'tag_name': tag,
    'name': 'SmartStore $tag',
    'html_url': 'https://github.com/$_owner/$_repository/releases/tag/$tag',
    'draft': draft,
    'prerelease': prerelease,
    'body': '## Improvements\n- Faster startup\n- Fixed stock report',
    'assets': [
      {
        'name': assetName,
        'browser_download_url': installerUrl ?? '$releasePath/$assetName',
        'size': 2048,
      },
      {
        'name': '$assetName.sha256',
        'browser_download_url': '$releasePath/$assetName.sha256',
        'size': 90,
      },
    ],
  };
}

void main() {
  test('compares full semantic versions, prereleases, and build metadata', () {
    expect(UpdateService.compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(UpdateService.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
    expect(UpdateService.compareVersions('1.0.0-alpha', '1.0.0'), lessThan(0));
    expect(UpdateService.compareVersions('1.0.0+8', '1.0.0'), equals(0));
    expect(
      UpdateService.compareVersions('1.0.0-rc.2', '1.0.0-rc.10'),
      lessThan(0),
    );
    expect(
      () => UpdateService.compareVersions('1.01.0', '1.1.0'),
      throwsFormatException,
    );
  });

  test('parses trusted GitHub release assets and changelog', () {
    final info = UpdateInfo.fromGitHubRelease(
      _release(),
      owner: _owner,
      repository: _repository,
    );

    expect(info.version, '1.1.0');
    expect(info.title, 'SmartStore v1.1.0');
    expect(info.downloadUrl.host, 'github.com');
    expect(
      info.checksumUrl.pathSegments.last,
      'SmartStore-Setup-1.1.0.exe.sha256',
    );
    expect(info.releaseNotes, [
      '## Improvements',
      'Faster startup',
      'Fixed stock report',
    ]);
    expect(info.sizeBytes, 2048);
  });

  test('rejects release URLs outside the configured GitHub repository', () {
    expect(
      () => UpdateInfo.fromGitHubRelease(
        _release(
          installerUrl:
              'https://evil.example/$_owner/$_repository/releases/download/v1.1.0/SmartStore-Setup-1.1.0.exe',
        ),
        owner: _owner,
        repository: _repository,
      ),
      throwsFormatException,
    );
    expect(
      () => UpdateInfo.fromGitHubRelease(
        _release(tag: '1.1.0', draft: true),
        owner: _owner,
        repository: _repository,
      ),
      throwsFormatException,
    );
  });

  test('gracefully handles an empty GitHub Releases page', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/repos/$_owner/$_repository/releases/latest');
      return http.Response('', 404);
    });
    final service = UpdateService(
      owner: _owner,
      repository: _repository,
      currentVersion: '1.0.0',
      client: client,
    );
    addTearDown(service.dispose);

    expect(await service.checkForUpdate(force: true), isNull);
    expect(service.status, UpdateStatus.idle);
    expect(service.update, isNull);
  });

  test('marks GitHub check failures so the user can retry', () async {
    final client = MockClient((request) async => http.Response('', 500));
    final service = UpdateService(
      owner: _owner,
      repository: _repository,
      currentVersion: '1.0.0',
      client: client,
    );
    addTearDown(service.dispose);

    expect(await service.checkForUpdate(force: true), isNull);
    expect(service.status, UpdateStatus.checkFailed);
    expect(service.update, isNull);
  });

  test('finds a newer release and fetches its checksum', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/releases/latest')) {
        return http.Response(jsonEncode(_release()), 200);
      }
      if (request.url.path.endsWith('.exe.sha256')) {
        return http.Response(
          '$_installerHash  SmartStore-Setup-1.1.0.exe',
          200,
        );
      }
      return http.Response('', 404);
    });
    final service = UpdateService(
      owner: _owner,
      repository: _repository,
      currentVersion: '1.0.0',
      client: client,
    );
    addTearDown(service.dispose);

    final update = await service.checkForUpdate(force: true);

    expect(update?.version, '1.1.0');
    expect(update?.sha256, _installerHash);
    expect(service.status, UpdateStatus.available);
  });

  test('does not fetch checksum when already current', () async {
    var checksumRequested = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/releases/latest')) {
        return http.Response(jsonEncode(_release(tag: 'v1.0.0')), 200);
      }
      checksumRequested = true;
      return http.Response('', 500);
    });
    final service = UpdateService(
      owner: _owner,
      repository: _repository,
      currentVersion: '1.0.0',
      client: client,
    );
    addTearDown(service.dispose);

    expect(await service.checkForUpdate(force: true), isNull);
    expect(checksumRequested, isFalse);
    expect(service.status, UpdateStatus.idle);
  });
}

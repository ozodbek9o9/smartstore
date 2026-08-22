import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/update_info.dart';

enum UpdateStatus {
  idle,
  checking,
  available,
  downloading,
  verifying,
  installing,
  restarting,
  failed,
}

class UpdateService extends ChangeNotifier {
  UpdateService({
    this.manifestUri = defaultManifestUri,
    this.currentVersion = currentAppVersion,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const defaultManifestUri =
      'https://neowhite-studio.vercel.app/smartstore/version.json';
  static const currentAppVersion = String.fromEnvironment(
    'SMARTSTORE_VERSION',
    defaultValue: '1.0.0',
  );

  final String manifestUri;
  final String currentVersion;
  final http.Client _client;
  UpdateInfo? update;
  UpdateStatus status = UpdateStatus.idle;
  double? progress;
  String? errorMessage;
  Timer? _periodicTimer;
  bool _operationInProgress = false;

  bool get isUpdating => _operationInProgress;

  void start() {
    unawaited(checkForUpdate());
    _periodicTimer ??= Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(checkForUpdate()),
    );
  }

  Future<UpdateInfo?> checkForUpdate() async {
    if (_operationInProgress) return update;
    status = UpdateStatus.checking;
    notifyListeners();
    try {
      final uri = Uri.tryParse(manifestUri);
      if (uri == null || uri.scheme != 'https') {
        throw const FormatException('Manifest URL must use HTTPS');
      }
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200)
        throw HttpException('Update server unavailable');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map)
        throw const FormatException('Invalid update manifest');
      final candidate = UpdateInfo.fromJson(Map<String, dynamic>.from(decoded));
      if (compareVersions(candidate.version, currentVersion) > 0) {
        update = candidate;
        status = UpdateStatus.available;
      } else {
        update = null;
        status = UpdateStatus.idle;
      }
    } catch (_) {
      status = UpdateStatus.idle;
    }
    notifyListeners();
    return update;
  }

  Future<void> install() async {
    final candidate = update;
    if (candidate == null || _operationInProgress || !Platform.isWindows)
      return;
    _operationInProgress = true;
    errorMessage = null;
    progress = 0;
    status = UpdateStatus.downloading;
    notifyListeners();

    Directory? temporaryDirectory;
    try {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'smartstore-update-',
      );
      final packageFile = File('${temporaryDirectory.path}\\update.zip');
      final request = http.Request('GET', candidate.downloadUrl);
      final response = await _client
          .send(request)
          .timeout(const Duration(minutes: 10));
      if (response.statusCode != 200)
        throw HttpException('Update download failed');
      final total = response.contentLength ?? candidate.sizeBytes;
      var received = 0;
      final sink = packageFile.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        progress = total == null ? null : received / total;
        notifyListeners();
      }
      await sink.close();

      status = UpdateStatus.verifying;
      progress = null;
      notifyListeners();
      final digest = sha256.convert(await packageFile.readAsBytes()).toString();
      if (digest.toLowerCase() != candidate.sha256) {
        throw const FormatException('Update SHA-256 mismatch');
      }
      if (candidate.sizeBytes != null &&
          packageFile.lengthSync() != candidate.sizeBytes) {
        throw const FormatException('Update size mismatch');
      }

      status = UpdateStatus.installing;
      notifyListeners();
      final executable = File(Platform.resolvedExecutable);
      final updater = File('${executable.parent.path}\\updater.exe');
      if (!await updater.exists())
        throw FileSystemException('updater.exe not found');
      final result = await Process.start(updater.path, [
        '--parent-pid',
        pid.toString(),
        '--install-dir',
        executable.parent.path,
        '--package',
        packageFile.path,
        '--sha256',
        candidate.sha256,
        '--restart-exe',
        executable.path,
      ], mode: ProcessStartMode.detached);
      result.stdout.drain<void>();
      result.stderr.drain<void>();
      status = UpdateStatus.restarting;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    } catch (error) {
      errorMessage = error.toString();
      status = UpdateStatus.failed;
      _operationInProgress = false;
      notifyListeners();
      if (temporaryDirectory != null) {
        try {
          await temporaryDirectory.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _client.close();
    super.dispose();
  }

  static int compareVersions(String left, String right) {
    final a = _parseVersion(left);
    final b = _parseVersion(right);
    for (var i = 0; i < 3; i++) {
      final comparison = a[i].compareTo(b[i]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static List<int> _parseVersion(String value) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(value.trim());
    if (match == null) throw const FormatException('Invalid semantic version');
    return [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }
}

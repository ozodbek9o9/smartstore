import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/update_environment.dart';
import '../models/update_info.dart';

enum UpdateStatus {
  idle,
  checking,
  available,
  downloading,
  verifying,
  installing,
  restarting,
  checkFailed,
  cancelled,
  failed,
}

class UpdateService extends ChangeNotifier {
  UpdateService({
    this.currentVersion = currentAppVersion,
    this.owner = UpdateEnvironment.githubOwner,
    this.repository = UpdateEnvironment.githubRepository,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const currentAppVersion = String.fromEnvironment(
    'SMARTSTORE_VERSION',
    defaultValue: '1.0.0',
  );

  final String currentVersion;
  final String owner;
  final String repository;
  final http.Client _client;
  UpdateInfo? update;
  UpdateStatus status = UpdateStatus.idle;
  double? progress;
  String? errorMessage;
  DateTime? _lastCheckedAt;
  Future<UpdateInfo?>? _activeCheck;
  Completer<void>? _downloadAbort;
  bool _operationInProgress = false;

  bool get isUpdating => _operationInProgress;

  Future<UpdateInfo?> checkForUpdate({bool force = false}) {
    if (_operationInProgress) {
      return Future<UpdateInfo?>.value(update);
    }
    if (_activeCheck != null) return _activeCheck!;
    final lastChecked = _lastCheckedAt;
    if (!force &&
        lastChecked != null &&
        DateTime.now().difference(lastChecked) < const Duration(hours: 6)) {
      return Future<UpdateInfo?>.value(update);
    }
    status = UpdateStatus.checking;
    errorMessage = null;
    notifyListeners();
    final check = _performCheck();
    _activeCheck = check;
    return check.whenComplete(() => _activeCheck = null);
  }

  Future<UpdateInfo?> _performCheck() async {
    try {
      _lastCheckedAt = DateTime.now();
      final response = await _client
          .get(
            UpdateEnvironment.latestReleaseUriFor(owner, repository),
            headers: _githubHeaders,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 404) {
        update = null;
        status = UpdateStatus.idle;
        notifyListeners();
        return null;
      }
      if (response.statusCode != 200) {
        throw HttpException('GitHub unavailable');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Invalid GitHub release');
      }
      final candidate = UpdateInfo.fromGitHubRelease(
        Map<String, dynamic>.from(decoded),
        owner: owner,
        repository: repository,
      );
      if (compareVersions(candidate.version, currentVersion) <= 0) {
        update = null;
        status = UpdateStatus.idle;
        notifyListeners();
        return null;
      }

      final checksumResponse = await _client
          .get(candidate.checksumUrl, headers: _downloadHeaders)
          .timeout(const Duration(seconds: 10));
      if (checksumResponse.statusCode != 200) {
        throw const FormatException('Release checksum is unavailable');
      }
      final checksum = RegExp(
        r'\b[0-9a-fA-F]{64}\b',
      ).firstMatch(checksumResponse.body)?.group(0)?.toLowerCase();
      if (checksum == null) {
        throw const FormatException('Invalid release checksum');
      }
      update = candidate.withSha256(checksum);
      status = UpdateStatus.available;
    } catch (_) {
      update = null;
      status = UpdateStatus.checkFailed;
    }
    notifyListeners();
    return update;
  }

  void cancelDownload() {
    final abort = _downloadAbort;
    if (status == UpdateStatus.downloading &&
        abort != null &&
        !abort.isCompleted) {
      abort.complete();
    }
  }

  Future<void> install() async {
    final candidate = update;
    if (candidate == null || _operationInProgress || !Platform.isWindows) {
      return;
    }
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
      final packageFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}SmartStore-Setup-${candidate.version}.exe',
      );
      _downloadAbort = Completer<void>();
      final request = http.AbortableRequest(
        'GET',
        candidate.downloadUrl,
        abortTrigger: _downloadAbort!.future,
      )..headers.addAll(_downloadHeaders);
      final response = await _client
          .send(request)
          .timeout(const Duration(minutes: 10));
      if (response.statusCode != 200) {
        throw HttpException('Update download failed');
      }
      final total = response.contentLength ?? candidate.sizeBytes;
      var received = 0;
      final sink = packageFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          progress = total <= 0 ? null : received / total;
          notifyListeners();
        }
      } finally {
        await sink.close();
      }

      status = UpdateStatus.verifying;
      progress = null;
      notifyListeners();
      final digest = sha256.convert(await packageFile.readAsBytes()).toString();
      if (digest.toLowerCase() != candidate.sha256) {
        throw const FormatException('Update SHA-256 mismatch');
      }
      if (candidate.sizeBytes > 0 &&
          packageFile.lengthSync() != candidate.sizeBytes) {
        throw const FormatException('Update size mismatch');
      }

      status = UpdateStatus.installing;
      notifyListeners();
      await Process.start(packageFile.path, [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
      ], mode: ProcessStartMode.detached);
      status = UpdateStatus.restarting;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      exit(0);
    } on http.RequestAbortedException {
      status = UpdateStatus.cancelled;
      errorMessage = null;
      _operationInProgress = false;
      progress = null;
      notifyListeners();
      if (temporaryDirectory != null) {
        try {
          await temporaryDirectory.delete(recursive: true);
        } catch (_) {}
      }
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
    } finally {
      _downloadAbort = null;
      _operationInProgress = false;
    }
  }

  @override
  void dispose() {
    cancelDownload();
    _client.close();
    super.dispose();
  }

  static int compareVersions(String left, String right) {
    return UpdateServiceVersion.compare(left, right);
  }

  static const _githubHeaders = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'SmartStore-Updater',
  };
  static const _downloadHeaders = {
    'Accept': 'application/octet-stream',
    'User-Agent': 'SmartStore-Updater',
  };
}

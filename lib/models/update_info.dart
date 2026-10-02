import '../config/update_environment.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.title,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.checksumUrl,
    required this.sha256,
    required this.releaseNotes,
    required this.sizeBytes,
  });

  final String version;
  final String title;
  final Uri releaseUrl;
  final Uri downloadUrl;
  final Uri checksumUrl;
  final String sha256;
  final List<String> releaseNotes;
  final int sizeBytes;

  UpdateInfo withSha256(String value) => UpdateInfo(
    version: version,
    title: title,
    releaseUrl: releaseUrl,
    downloadUrl: downloadUrl,
    checksumUrl: checksumUrl,
    sha256: value,
    releaseNotes: releaseNotes,
    sizeBytes: sizeBytes,
  );

  factory UpdateInfo.fromGitHubRelease(
    Map<String, dynamic> json, {
    required String owner,
    required String repository,
  }) {
    final tag = json['tag_name']?.toString().trim() ?? '';
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (!UpdateServiceVersion.isValid(version) ||
        json['draft'] == true ||
        json['prerelease'] == true) {
      throw const FormatException('Invalid GitHub release version');
    }

    final releaseUrl = _trustedGitHubUrl(
      json['html_url']?.toString(),
      owner: owner,
      repository: repository,
    );
    if (releaseUrl.pathSegments.length != 5 ||
        releaseUrl.pathSegments[2] != 'releases' ||
        releaseUrl.pathSegments[3] != 'tag' ||
        releaseUrl.pathSegments[4] != tag) {
      throw const FormatException('Invalid GitHub release page URL');
    }
    final installerName = '${UpdateEnvironment.installerPrefix}$version.exe';
    final assets = json['assets'];
    if (assets is! List) {
      throw const FormatException('GitHub release has no assets');
    }
    Map<String, dynamic>? installer;
    Map<String, dynamic>? checksum;
    for (final item in assets) {
      if (item is! Map) continue;
      final asset = Map<String, dynamic>.from(item);
      if (asset['name'] == installerName) installer = asset;
      if (asset['name'] == '$installerName.sha256') checksum = asset;
    }
    if (installer == null || checksum == null) {
      throw const FormatException(
        'Release must include the SmartStore installer and its .sha256 file',
      );
    }

    final body = json['body']?.toString() ?? '';
    final notes = body
        .split('\n')
        .map((line) => line.trim().replaceFirst(RegExp(r'^[-*]\s+'), ''))
        .where((line) => line.isNotEmpty)
        .take(30)
        .toList(growable: false);

    return UpdateInfo(
      version: version,
      title: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : 'SmartStore $version',
      releaseUrl: releaseUrl,
      downloadUrl: _trustedAssetUrl(
        installer['browser_download_url']?.toString(),
        owner: owner,
        repository: repository,
        tag: tag,
        expectedName: installerName,
      ),
      checksumUrl: _trustedAssetUrl(
        checksum['browser_download_url']?.toString(),
        owner: owner,
        repository: repository,
        tag: tag,
        expectedName: '$installerName.sha256',
      ),
      sha256: '',
      releaseNotes: notes,
      sizeBytes: installer['size'] is num
          ? (installer['size'] as num).toInt()
          : 0,
    );
  }

  static Uri _trustedGitHubUrl(
    String? value, {
    required String owner,
    required String repository,
  }) {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.pathSegments.length < 5 ||
        uri.pathSegments[0] != owner ||
        uri.pathSegments[1] != repository) {
      throw const FormatException(
        'Release URL is not from the configured repository',
      );
    }
    return uri;
  }

  static Uri _trustedAssetUrl(
    String? value, {
    required String owner,
    required String repository,
    required String tag,
    required String expectedName,
  }) {
    final uri = _trustedGitHubUrl(value, owner: owner, repository: repository);
    if (uri.pathSegments.length != 6 ||
        uri.pathSegments[2] != 'releases' ||
        uri.pathSegments[3] != 'download' ||
        uri.pathSegments[4] != tag ||
        uri.pathSegments[5] != expectedName) {
      throw const FormatException('Invalid GitHub release asset URL');
    }
    return uri;
  }
}

class UpdateServiceVersion {
  UpdateServiceVersion._();

  static bool isValid(String value) => _parse(value) != null;

  static int compare(String left, String right) {
    final a = _parse(left);
    final b = _parse(right);
    if (a == null || b == null) {
      throw const FormatException('Invalid semantic version');
    }
    for (var index = 0; index < 3; index++) {
      final comparison = a.parts[index].compareTo(b.parts[index]);
      if (comparison != 0) return comparison;
    }
    if (a.preRelease.isEmpty || b.preRelease.isEmpty) {
      if (a.preRelease.isEmpty == b.preRelease.isEmpty) return 0;
      return a.preRelease.isEmpty ? 1 : -1;
    }
    final count = a.preRelease.length < b.preRelease.length
        ? a.preRelease.length
        : b.preRelease.length;
    for (var index = 0; index < count; index++) {
      final leftPart = a.preRelease[index];
      final rightPart = b.preRelease[index];
      final leftNumeric = int.tryParse(leftPart);
      final rightNumeric = int.tryParse(rightPart);
      final comparison = leftNumeric != null && rightNumeric != null
          ? leftNumeric.compareTo(rightNumeric)
          : leftNumeric != null
          ? -1
          : rightNumeric != null
          ? 1
          : leftPart.compareTo(rightPart);
      if (comparison != 0) return comparison;
    }
    return a.preRelease.length.compareTo(b.preRelease.length);
  }

  static _ParsedVersion? _parse(String value) {
    final match = RegExp(
      r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final preRelease = match.group(4)?.split('.') ?? const <String>[];
    if (preRelease.any((part) => RegExp(r'^0\d+$').hasMatch(part))) {
      return null;
    }
    return _ParsedVersion([
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ], preRelease);
  }
}

class _ParsedVersion {
  const _ParsedVersion(this.parts, this.preRelease);

  final List<int> parts;
  final List<String> preRelease;
}

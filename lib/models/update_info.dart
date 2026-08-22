class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    required this.releaseNotes,
    required this.mandatory,
    this.sizeBytes,
  });

  final String version;
  final Uri downloadUrl;
  final String sha256;
  final List<String> releaseNotes;
  final bool mandatory;
  final int? sizeBytes;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final version = json['version']?.toString().trim() ?? '';
    final downloadUrl = Uri.tryParse(json['downloadUrl']?.toString() ?? '');
    final sha256 = json['sha256']?.toString().trim().toLowerCase() ?? '';
    final rawNotes = json['releaseNotes'];

    if (version.isEmpty || downloadUrl == null || sha256.length != 64) {
      throw const FormatException('Invalid update manifest');
    }
    if (downloadUrl.scheme != 'https') {
      throw const FormatException('Update URL must use HTTPS');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid SHA-256 hash');
    }

    return UpdateInfo(
      version: version,
      downloadUrl: downloadUrl,
      sha256: sha256,
      releaseNotes: rawNotes is List
          ? rawNotes.map((note) => note.toString()).toList(growable: false)
          : const [],
      mandatory: json['mandatory'] == true,
      sizeBytes: json['sizeBytes'] is num
          ? (json['sizeBytes'] as num).toInt()
          : null,
    );
  }
}

class UpdateEnvironment {
  const UpdateEnvironment._();

  static const appwriteProjectId = '6a89daa60002f8486d30';
  static const appwriteProjectName = 'updates';
  static const appwritePublicEndpoint = 'https://fra.cloud.appwrite.io/v1';
  static const updatesBucketId = '6a89db6600013a5d5784';
  static const manifestFileId = 'version-json';

  static const manifestUrl =
      '$appwritePublicEndpoint/storage/buckets/$updatesBucketId/files/$manifestFileId/view?project=$appwriteProjectId';

  static String fileDownloadUrl(String fileId) =>
      '$appwritePublicEndpoint/storage/buckets/$updatesBucketId/files/$fileId/download?project=$appwriteProjectId';
}

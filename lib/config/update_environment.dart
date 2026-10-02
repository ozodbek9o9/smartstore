class UpdateEnvironment {
  const UpdateEnvironment._();

  static const githubOwner = 'ozodbek9o9';
  static const githubRepository = 'smartstore';
  static const installerPrefix = 'SmartStore-Setup-';
  static const githubApiBase = 'https://api.github.com';

  static Uri latestReleaseUriFor(String owner, String repository) =>
      Uri.parse('$githubApiBase/repos/$owner/$repository/releases/latest');
}

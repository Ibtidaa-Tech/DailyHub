/// Single source of truth for the app's version and where updates come from.
///
/// This is a plain Dart constant rather than the `package_info_plus` plugin on
/// purpose: your Android toolchain (AGP 9 / Kotlin 2.3) is ahead of what many
/// plugins support, and a hardcoded constant carries zero build risk.
///
/// WHEN YOU RELEASE A NEW BUILD, change these three things together:
///   1. `appVersion` below
///   2. `version:` in pubspec.yaml  (e.g. 1.1.0+2)
///   3. the git tag on the GitHub release (e.g. v1.1.0)
library;

class AppVersion {
  /// Current build's version. Must match the GitHub release tag (without 'v').
  static const String appVersion = '2.1.2';

  /// GitHub repo that hosts the APK releases.
  /// Change these if your repo is named differently.
  static const String githubOwner = 'Ibtidaa-Tech';
  static const String githubRepo = 'DailyHub';

  static String get releasesApi =>
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  static String get releasesPage =>
      'https://github.com/$githubOwner/$githubRepo/releases/latest';
}

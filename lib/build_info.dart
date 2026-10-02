/// Which build this is, so a finding on an APK can be matched to the exact commit that produced it. Set by
/// tool/build_release.dart through --dart-define; a plain `flutter run` has none and says "dev build". The APK's own
/// SHA-256 can't be inside it (it would change it): it goes in the release manifest next to the APK.
class BuildInfo {
  static const versionName = String.fromEnvironment('APP_VERSION_NAME');
  static const versionCode = String.fromEnvironment('APP_VERSION_CODE');
  static const commit = String.fromEnvironment('GIT_SHA');
  static const buildTime = String.fromEnvironment('BUILD_TIME');

  static bool get isRelease => commit.isNotEmpty;

  /// "v1.0.1 (2) · 3f2a9c1 · 2026-10-02T19:12:04Z", or "dev build".
  static String get label {
    if (!isRelease) return 'dev build';
    final short = commit.length > 7 ? commit.substring(0, 7) : commit;
    return 'v$versionName ($versionCode) · $short · $buildTime';
  }
}

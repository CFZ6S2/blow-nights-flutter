// Pure pieces of tool/build_release.dart, tested in test/release_manifest_test.dart: the version from pubspec.yaml,
// how the release build is signed, the build-time values a Play build may carry, and the manifest that goes next to
// the APK or AAB.

/// `version: 1.2.3+45` in pubspec.yaml → (name: "1.2.3", code: 45).
({String name, int code}) parsePubspecVersion(String pubspec) {
  final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', multiLine: true).firstMatch(pubspec);
  if (m == null) throw const FormatException('pubspec.yaml needs "version: x.y.z+N"');
  return (name: m.group(1)!, code: int.parse(m.group(2)!));
}

/// How the release build is signed: "upload" (the Play upload key, android/key.properties) when the release build
/// type uses it and the file is there; "debug" otherwise (Flutter's template, or no key on this machine).
String releaseSigning(String gradleKts, {required bool keyProperties}) {
  final release = RegExp(r'release\s*\{([^}]*)\}', dotAll: true).firstMatch(gradleKts)?.group(1) ?? '';
  return keyProperties && release.contains('signingConfigs.getByName("upload")') ? 'upload' : 'debug';
}

/// Build-time values that must never reach a Play build: the App Check debug token only exists so hand-installed APKs
/// (which can't pass Play Integrity) work; with it, anyone with the binary could pass App Check.
const playForbiddenDefines = ['APPCHECK_DEBUG_TOKEN'];

/// dart_defines.json without what a Play build must not carry.
Map<String, dynamic> playDefines(Map<String, dynamic> defines) =>
    {for (final e in defines.entries) if (!playForbiddenDefines.contains(e.key)) e.key: e.value};

/// The file name of a release (without extension): blow-nights-1.2.3+45-3f2a9c1.
String releaseBaseName(String versionName, int versionCode, String commit) =>
    'blow-nights-$versionName+$versionCode-${commit.substring(0, 7)}';

/// The manifest next to the APK (QA, installed by hand) or the AAB (Play). Every field must be there: an incomplete
/// manifest is an error, not a release.
Map<String, Object> buildManifest({
  String artifact = 'apk',
  bool obfuscated = false,
  required String applicationId,
  required String versionName,
  required int versionCode,
  required String commit,
  required String branch,
  required String buildTime,
  required String flutterVersion,
  required String signing,
  required List<String> dartDefineKeys,
  required String apkFile,
  required int apkBytes,
  required String apkSha256,
}) {
  final missing = <String>[
    if (applicationId.isEmpty) 'applicationId',
    if (versionName.isEmpty) 'versionName',
    if (versionCode <= 0) 'versionCode',
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) 'commit',
    if (branch.isEmpty) 'branch',
    if (DateTime.tryParse(buildTime) == null) 'buildTime',
    if (flutterVersion.isEmpty) 'flutterVersion',
    if (signing.isEmpty) 'signing',
    if (apkFile.isEmpty) 'apkFile',
    if (apkBytes <= 0) 'apkBytes',
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(apkSha256)) 'apkSha256',
    if (artifact != 'apk' && artifact != 'aab') 'artifact',
  ];
  if (missing.isNotEmpty) throw StateError('incomplete release manifest: ${missing.join(', ')}');
  return {
    'app': 'blow_nights',
    'applicationId': applicationId,
    'variant': artifact == 'aab' ? 'play' : 'release',
    'versionName': versionName,
    'versionCode': versionCode,
    'commit': commit,
    'commitShort': commit.substring(0, 7),
    'branch': branch,
    'buildTime': buildTime,
    'flutterVersion': flutterVersion,
    'signing': signing,
    // Which build-time values were set; never their contents (App Check token, API keys).
    'dartDefines': [...dartDefineKeys]..sort(),
    'obfuscated': obfuscated,
    artifact: {'file': apkFile, 'bytes': apkBytes, 'sha256': apkSha256},
  };
}

/// A previous release manifest with the same versionCode but another commit means the version wasn't bumped: two
/// different APKs would carry the same versionCode.
String? versionCodeClash(Iterable<Map<String, dynamic>> previous, int versionCode, String commit) {
  for (final m in previous) {
    if (m['versionCode'] == versionCode && m['commit'] != commit) {
      return 'versionCode $versionCode is already release ${m['commitShort'] ?? m['commit']}: bump the version in pubspec.yaml';
    }
  }
  return null;
}

import 'package:flutter_test/flutter_test.dart';

import '../tool/release_manifest.dart';

void main() {
  const commit = '3f2a9c1d0e4b5a6978c1d2e3f4a5b6c7d8e9f0a1';
  Map<String, Object> manifest({String c = commit, String? sha, int code = 2, String buildTime = '2026-10-02T19:12:04Z'}) =>
      buildManifest(
        applicationId: 'com.blownights.finder',
        versionName: '1.0.1',
        versionCode: code,
        commit: c,
        branch: 'main',
        buildTime: buildTime,
        flutterVersion: '3.47.5',
        signing: 'debug',
        dartDefineKeys: ['PLACES_API_KEY', 'APPCHECK_DEBUG_TOKEN', 'GIT_SHA'],
        apkFile: 'blow-nights-1.0.1+2-3f2a9c1.apk',
        apkBytes: 123,
        apkSha256: sha ?? 'ab' * 32,
      );

  test('version from pubspec.yaml', () {
    expect(parsePubspecVersion('name: x\nversion: 1.2.3+45\n'), (name: '1.2.3', code: 45));
    expect(() => parsePubspecVersion('version: 1.2.3\n'), throwsFormatException);
  });

  test('release signing read from the Gradle build type', () {
    expect(releaseSigning('buildTypes {\n release {\n signingConfig = signingConfigs.getByName("debug")\n }\n}'), 'debug');
    expect(releaseSigning('buildTypes {\n release {\n signingConfig = signingConfigs.getByName("release")\n }\n}'), 'release');
  });

  test('the manifest has commit, versions, build time and the APK SHA-256; define keys only, sorted', () {
    final m = manifest();
    expect(m['commit'], commit);
    expect(m['commitShort'], '3f2a9c1');
    expect(m['versionCode'], 2);
    expect(m['buildTime'], '2026-10-02T19:12:04Z');
    expect(m['dartDefines'], ['APPCHECK_DEBUG_TOKEN', 'GIT_SHA', 'PLACES_API_KEY']);
    expect(m['apk'], {'file': 'blow-nights-1.0.1+2-3f2a9c1.apk', 'bytes': 123, 'sha256': 'ab' * 32});
    expect(releaseBaseName('1.0.1', 2, commit), 'blow-nights-1.0.1+2-3f2a9c1');
  });

  test('an incomplete manifest is an error, never written', () {
    expect(() => manifest(c: 'abc'), throwsStateError);
    expect(() => manifest(sha: 'not-a-hash'), throwsStateError);
    expect(() => manifest(code: 0), throwsStateError);
    expect(() => manifest(buildTime: 'yesterday'), throwsStateError);
  });

  test('a versionCode already released from another commit must be bumped', () {
    final previous = [
      {'versionCode': 2, 'commit': 'f' * 40, 'commitShort': 'fffffff'},
    ];
    expect(versionCodeClash(previous, 2, commit), contains('bump the version'));
    expect(versionCodeClash(previous, 3, commit), isNull);
    expect(versionCodeClash([{'versionCode': 2, 'commit': commit}], 2, commit), isNull); // the same build again
  });
}

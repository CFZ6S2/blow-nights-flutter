// Release builds with provenance: every APK or AAB can be matched to the exact commit that produced it.
//
//   dart run tool/build_release.dart          QA APK, installed by hand (debug keys unless the upload key is there;
//                                              carries the App Check debug token: sideloaded APKs can't pass Play Integrity)
//   dart run tool/build_release.dart --play   Google Play AAB: signed with the upload key (android/key.properties,
//                                              required), obfuscated (symbols in build/release/symbols/<name>), and
//                                              WITHOUT the App Check debug token (Play Integrity)
//
// Refuses to build unless the tree is clean, HEAD is pushed and dart_defines.json is there. Builds
// `flutter build apk --release` with dart_defines.json plus GIT_SHA, BUILD_TIME, APP_VERSION_NAME and APP_VERSION_CODE
// (shown in the app: lib/build_info.dart, at the bottom of the profile), then writes to build/release/:
//   blow-nights-<versionName>+<versionCode>-<sha7>.apk
//   blow-nights-<versionName>+<versionCode>-<sha7>.json   commit, versions, build time, Flutter, signing, the
//                                                           dart-define keys (never their values) and the APK's SHA-256
// The SHA-256 can't go inside the APK (it would change it), so it lives in the manifest. A versionCode already used by
// another commit's release, or any missing field, stops the build: no incomplete manifest is ever written.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'release_manifest.dart';

Future<String> run(String exe, List<String> args) async {
  final r = await Process.run(exe, args, runInShell: true);
  if (r.exitCode != 0) throw ProcessException(exe, args, '${r.stderr}'.trim(), r.exitCode);
  return '${r.stdout}'.trim();
}

Never fail(String message) {
  stderr.writeln('build_release: $message');
  exit(1);
}

Future<void> main(List<String> args) async {
  final play = args.contains('--play');
  // Provenance: a clean tree at a commit that exists on the remote.
  if ((await run('git', ['status', '--porcelain'])).isNotEmpty) fail('the working tree has changes: commit or stash them first');
  final commit = await run('git', ['rev-parse', 'HEAD']);
  final branch = await run('git', ['rev-parse', '--abbrev-ref', 'HEAD']);
  await run('git', ['fetch', '--quiet', 'origin']);
  if ((await run('git', ['branch', '-r', '--contains', commit])).isEmpty) fail('HEAD $commit is not on origin: push it first');

  final defines = File('dart_defines.json');
  if (!defines.existsSync()) fail('dart_defines.json is missing (App Check token, Places key)');
  final allDefines = jsonDecode(defines.readAsStringSync()) as Map<String, dynamic>;
  final buildDefines = play ? playDefines(allDefines) : allDefines;
  final defineKeys = buildDefines.keys.toList();

  final version = parsePubspecVersion(File('pubspec.yaml').readAsStringSync());
  final out = Directory('build/release')..createSync(recursive: true);
  final previous = out.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))
      .map((f) => jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  final clash = versionCodeClash(previous, version.code, commit);
  if (clash != null) fail(clash);

  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final applicationId = RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle)?.group(1) ?? '';
  final signing = releaseSigning(gradle, keyProperties: File('android/key.properties').existsSync());
  if (play && signing != 'upload') fail('a Play build needs the upload key: android/key.properties (see README, "Google Play")');
  final flutterVersion = (jsonDecode(await run('flutter', ['--version', '--machine'])) as Map<String, dynamic>)['frameworkVersion'] as String? ?? '';
  final buildTime = DateTime.now().toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

  final base = releaseBaseName(version.name, version.code, commit);
  // A Play build reads its defines from a filtered copy (under build/, never in git).
  final definesFile = play ? (File('build/play_defines.json')..writeAsStringSync(jsonEncode(buildDefines))) : defines;
  final symbols = '${out.path}/symbols/$base';

  stdout.writeln('Building ${play ? 'AAB (Play)' : 'APK'} ${version.name}+${version.code} at ${commit.substring(0, 7)} ($branch), signing: $signing');
  final build = await Process.start('flutter', [
    'build', play ? 'appbundle' : 'apk', '--release',
    if (play) ...['--obfuscate', '--split-debug-info=$symbols'],
    '--dart-define-from-file=${definesFile.path}',
    '--dart-define=GIT_SHA=$commit',
    '--dart-define=BUILD_TIME=$buildTime',
    '--dart-define=APP_VERSION_NAME=${version.name}',
    '--dart-define=APP_VERSION_CODE=${version.code}',
  ], runInShell: true, mode: ProcessStartMode.inheritStdio);
  final exitCode = await build.exitCode;
  if (play) definesFile.deleteSync();
  if (exitCode != 0) fail('flutter build ${play ? 'appbundle' : 'apk'} failed');

  final ext = play ? 'aab' : 'apk';
  final built = File(play ? 'build/app/outputs/bundle/release/app-release.aab' : 'build/app/outputs/flutter-apk/app-release.apk');
  if (!built.existsSync()) fail('no $ext at ${built.path}');
  final artifactFile = built.copySync('${out.path}/$base.$ext');
  final bytes = artifactFile.readAsBytesSync();
  final manifest = buildManifest(
    artifact: ext,
    obfuscated: play,
    applicationId: applicationId,
    versionName: version.name,
    versionCode: version.code,
    commit: commit,
    branch: branch,
    buildTime: buildTime,
    flutterVersion: flutterVersion,
    signing: signing,
    dartDefineKeys: [...defineKeys, 'GIT_SHA', 'BUILD_TIME', 'APP_VERSION_NAME', 'APP_VERSION_CODE'],
    apkFile: '$base.$ext',
    apkBytes: bytes.length,
    apkSha256: sha256.convert(bytes).toString(),
  );
  File('${out.path}/$base.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
  stdout.writeln('Release: ${out.path}/$base.$ext');
  stdout.writeln('SHA-256: ${(manifest[ext] as Map)['sha256']}');
  if (play) stdout.writeln('Symbols (keep them to read crash stack traces): $symbols');
  if (signing == 'debug') {
    stdout.writeln('Note: signed with the debug keys (android/app/build.gradle.kts). Fine to install by hand; not for the Play Store.');
  }
}

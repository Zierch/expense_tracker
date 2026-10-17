// Security invariants for the release build and deployment.
//
// This app is published as a shared APK with personal financial records
// stored on-device. These tests lock in decisions that a future contributor
// could silently break, causing users to lose data or exposing backups.
//
// Read files from disk and assert that each invariant still holds.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Exception thrown when git binary is not available on the host.
/// This is a host property (not a code defect), so tests may skip on this.
class _GitNotAvailableException implements Exception {
  final String message;
  const _GitNotAvailableException(this.message);
  @override
  String toString() => message;
}

/// Every data domain the extraction rules format documents.
///
/// Both sections of the rules file list all nine rather than relying on the root
/// domain's recursion, so the intent does not depend on how the backup engine
/// walks its domains.
const List<String> _allDomains = <String>[
  'root',
  'file',
  'database',
  'sharedpref',
  'external',
  'device_root',
  'device_file',
  'device_database',
  'device_sharedpref',
];

/// The data extraction rules, which decide what Android may copy off the device.
const String _rulesPath =
    'android/app/src/main/res/xml/data_extraction_rules.xml';

void main() {
  group('release build signing', () {
    test(
      'release build type must not fall back to debug keystore',
      () {
        final String gradleSource =
            File('android/app/build.gradle.kts').readAsStringSync();

        // The Flutter template ships `signingConfig = signingConfigs.getByName("debug")`
        // for release builds. Removing that line is what closes the hole: a debug-signed
        // APK is per-machine and recreatable, so a rebuild from anywhere else forces
        // every user to uninstall, deleting their financial database in the process.
        //
        // Forbidden as the quoted token rather than as one call shape, because Gradle
        // can reach a signing config through getByName("debug") or signingConfigs["debug"],
        // and checking only the first spelling leaves the second as a way back in.
        //
        // This is the one assertion here that forbids something, so it cannot afford a
        // classifier that fails quietly: a missed token ships a debug-signed APK, and
        // that costs every user their database when they next try to upgrade.
        // _debugSigningOffenders asks two classifiers with opposite blind spots and is
        // satisfied only when both come back clean.
        final List<String> offenders = _debugSigningOffenders(gradleSource);

        expect(
          offenders,
          isEmpty,
          reason:
              'SECURITY: nothing in build.gradle.kts may reference the debug signing '
              'config on a live line, in any spelling. If release used it, the shared '
              'APK would be signed with a per-machine keystore, so rebuilding anywhere '
              'else would force every user to uninstall, which deletes their financial '
              'database. If a build type genuinely needs the debug config named, change '
              'this test deliberately rather than working around it. '
              'Offending line(s): $offenders',
        );
      },
    );

    test('release signing must load credentials from key.properties', () {
      final String gradle = _kotlinCode(
        File('android/app/build.gradle.kts').readAsStringSync(),
      );

      expect(
        gradle,
        stringContainsInOrder([
          'keystorePropertiesFile = rootProject.file("key.properties")',
        ]),
        reason:
            'SECURITY: release build must load signing credentials from '
            'android/key.properties (git-ignored); without this, the release '
            'variant falls back to unsigned or debug-signed.',
      );
    });

    test('the release build type must be given the release signing config', () {
      final String gradle = _kotlinCode(
        File('android/app/build.gradle.kts').readAsStringSync(),
      );

      // Not naming a debug config is only half of the invariant. The release build
      // type also has to be handed the release config, or it ships unsigned: users
      // get an APK they cannot upgrade without uninstalling first, which deletes
      // their financial database.
      expect(
        gradle,
        contains('signingConfig = signingConfigs.getByName("release")'),
        reason:
            'SECURITY: the release build type must assign signingConfig = '
            'signingConfigs.getByName("release").',
      );
    });

    test('key.properties must be git-ignored, never committed', () {
      // Existing on disk is fine and expected: anybody who follows
      // README.md -> "Building a release APK" keeps a real file there, and
      // their `flutter test` run has to stay green. The dangerous state is a
      // *tracked* key.properties, so ask git rather than the filesystem.
      final String gitignore = File('.gitignore').readAsStringSync();
      expect(
        gitignore,
        contains('key.properties'),
        reason:
            'SECURITY: the root .gitignore must cover key.properties; android/'
            '.gitignore only matches paths inside android/, so without this a '
            'signing password could be committed.',
      );

      // A worktree or a submodule keeps .git as a *file* rather than a directory,
      // so testing only for a directory would silently skip this check on exactly
      // those checkouts.
      final bool insideRepository =
          Directory('.git').existsSync() || File('.git').existsSync();
      if (!insideRepository) return;

      // Exit 0 means git will ignore the path. Exit 1 means it will not, which
      // covers both "untracked and unignored" and "already tracked", since ignore
      // rules never apply to a file git already tracks. Anything else means the
      // check did not run, and that has to fail too: treating "could not verify"
      // as a pass is how a guard quietly stops guarding.
      final ProcessResult result;
      try {
        result = Process.runSync(
          'git',
          <String>['check-ignore', '-q', 'android/key.properties'],
        );
      } on ProcessException {
        return; // git is not installed here; there is nothing to ask.
      }

      expect(
        result.exitCode,
        0,
        reason:
            'SECURITY: git must report android/key.properties as ignored. Exit 1 '
            'means it is not, so the signing keystore password can be committed by '
            'accident; any other exit code means the check itself failed to run.',
      );
    });

    test('root .gitignore must cover keystores and key.properties', () {
      final String gitignore = File('.gitignore').readAsStringSync();

      expect(
        gitignore,
        stringContainsInOrder(['*.jks', '*.keystore', 'key.properties']),
        reason:
            'SECURITY: root .gitignore must explicitly cover *.jks, *.keystore, '
            'and key.properties. The android/.gitignore only covers paths *within* '
            'android/, so a keystore dropped anywhere else in the tree would sail '
            'past it; the root patterns catch that.',
      );
    });

    test('root .gitignore must cover local data and review notes', () {
      final String gitignore = File('.gitignore').readAsStringSync();

      // Two of these are worse than clutter. A SQLite file or an export dump is
      // somebody's real financial history, and the review notes describe how to
      // attack this app. Neither may travel in a repository that gets published.
      for (final String pattern in <String>[
        '*.sqlite',
        '*.db',
        'local.properties',
        'docs/audit/',
      ]) {
        expect(
          gitignore,
          contains(pattern),
          reason:
              'SECURITY: root .gitignore must cover $pattern. The android/ '
              '.gitignore only matches paths inside android/, so a file dropped '
              'elsewhere in the tree would be committed.',
        );
      }
    });
    test('release signing must also be enforced on the packaging task', () {
      final String gradle = _kotlinCode(
        File('android/app/build.gradle.kts').readAsStringSync(),
      );

      // The friendly check keys off the requested task *name*, which is not
      // enough on its own: `./gradlew assemble`, `./gradlew build` and Gradle's
      // camel-case abbreviations (`aR`) all reach the release variant without
      // the string "Release" ever appearing in startParameter.taskNames. The
      // guard that actually holds therefore hangs off the packaging task, which
      // exists precisely when a release artifact is about to be produced.
      expect(
        gradle,
        contains('tasks.configureEach'),
        reason:
            'SECURITY: without a guard on the packaging task itself, a release '
            'build requested as `assemble`, `build` or `aR` walks past the '
            'task-name check and yields an unsigned artifact.',
      );
      expect(
        gradle,
        contains('startsWith("package")'),
        reason: 'SECURITY: the packaging-task guard must target the package* tasks.',
      );
      expect(
        gradle,
        contains('doFirst'),
        reason:
            'SECURITY: the packaging-task guard must run before the task body, '
            'not merely during configuration.',
      );
      expect(
        gradle,
        contains('GradleException'),
        reason:
            'SECURITY: the packaging-task guard must actually raise. A doFirst '
            'block that runs but no longer throws leaves the task-name check as the '
            'only protection, and `assemble`, `build` and `aR` all walk past it.',
      );
    });
  });

  group('auto backup and device-to-device transfer', () {
    test('AndroidManifest must disable auto backup', () {
      final String manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      expect(
        manifest,
        contains('android:allowBackup="false"'),
        reason:
            'SECURITY: AndroidManifest must set android:allowBackup="false" to '
            'prevent Android from automatically backing up the SQLite database '
            'to Google Drive without user consent. The app exposes backup only '
            'through an explicit "Backup" button.',
      );
    });

    test('AndroidManifest must reference the data extraction rules file', () {
      final String manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      // allowBackup="false" and the rules file do different jobs. Delete this one
      // attribute and allowBackup="false" still stands, so the test above stays
      // green while the device-to-device exclusion silently stops being applied --
      // which is the Android 12+ case the rules file exists for.
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
        reason:
            'SECURITY: AndroidManifest must point at the data extraction rules. '
            'Without that attribute the file has no effect at all, and only '
            'allowBackup="false" remains, which Google documents as still '
            'permitting device-to-device transfer on Android 12+ for some '
            'manufacturers.',
      );
    });

    test('the rules file must keep the documented root element', () {
      final String rules = _xmlElements(File(_rulesPath).readAsStringSync());

      // Android checks the root tag when it reads this file. A typo here means the
      // whole file is ignored, and nothing the user could observe would say so.
      expect(
        rules,
        contains('<data-extraction-rules>'),
        reason:
            'SECURITY: the root element must be <data-extraction-rules>. The '
            'platform verifies that tag, and an unrecognised root means every '
            'exclusion in the file is skipped.',
      );
    });

    test('the rules file must not opt into cross-platform transfer', () {
      final String rules = _xmlElements(File(_rulesPath).readAsStringSync());

      // cloud-backup and device-transfer are enabled unless excluded, which is why
      // both sections exist. Cross-platform transfer to iOS works the other way
      // round: AOSP only lets an app take part if it opts in here, and opting in
      // also requires <platform-specific-params> naming the counterpart iOS app's
      // bundleId and teamId. This app is Android-only, so staying out is the safe
      // state, and this assertion stops a future reader from "completing" the file
      // by adding that section.
      expect(
        rules,
        isNot(contains('cross-platform-transfer')),
        reason:
            'SECURITY: do not add a <cross-platform-transfer> section. That route '
            'moves data between the same app on two platforms, and only to the '
            'counterpart named in <platform-specific-params>; this app is '
            'Android-only, so no counterpart can match and nothing would be '
            'exported. Adding the section would also declare a counterpart that '
            'does not exist. If an iOS version is ever built, add the section then '
            'and update this test deliberately.',
      );
    });

    test('data_extraction_rules must exclude every domain from cloud-backup', () {
      final String cloudBackup = _rulesSection('cloud-backup');

      expect(
        cloudBackup,
        isNotEmpty,
        reason:
            'SECURITY: data_extraction_rules.xml must contain a <cloud-backup> '
            'section. An absent section does not mean "nothing is backed up": '
            'Google documents that a missing section leaves that mode fully '
            'enabled.',
      );

      // All nine documented domains, not a sample. The file lists every one so the
      // intent does not depend on how the backup engine walks its domains, and a
      // two-domain check would stay green with seven exclusions deleted.
      for (final String domain in _allDomains) {
        expect(
          cloudBackup,
          matches(RegExp('exclude\\s+domain="$domain"\\s+path="\\."')),
          reason:
              'SECURITY: the cloud-backup section must exclude domain="$domain" '
              'with path=".". Without that exclusion the domain is backed up to '
              'Google Drive. This is asserted per section on purpose: a check that '
              'searched the whole file would also be satisfied by the '
              'device-transfer section, so deleting an exclusion from one section '
              'while the other still had it would pass.',
        );
      }
    });

    test(
        'data_extraction_rules must exclude every domain from device-transfer',
        () {
      final String deviceTransfer = _rulesSection('device-transfer');

      expect(
        deviceTransfer,
        isNotEmpty,
        reason:
            'SECURITY: data_extraction_rules.xml must contain a <device-transfer> '
            'section, because Google documents that on Android 12+ on some '
            'manufacturers\' devices android:allowBackup="false" stops cloud '
            'backup but still permits device-to-device transfer.',
      );

      for (final String domain in _allDomains) {
        expect(
          deviceTransfer,
          matches(RegExp('exclude\\s+domain="$domain"\\s+path="\\."')),
          reason:
              'SECURITY: the device-transfer section must exclude domain="$domain" '
              'with path="."; this is the path that allowBackup alone leaves open '
              'on Android 12+.',
        );
      }
    });
  });

  group('OAuth identity and configuration', () {
    test('package name must be consistent across all three locations', () {
      final String gradle =
          File('android/app/build.gradle.kts').readAsStringSync();
      final String mainActivity = File(
              'android/app/src/main/kotlin/com/zierch/expense_tracker/MainActivity.kt')
          .readAsStringSync();
      final String googleConfig =
          File('lib/data/services/google_config.dart').readAsStringSync();

      // Extract values from each file.
      final RegExp gradleNamespace = RegExp(r'namespace\s*=\s*"([^"]+)"');
      final RegExp gradleAppId = RegExp(r'applicationId\s*=\s*"([^"]+)"');
      final RegExp kotlinPackage = RegExp(r'package\s+([a-z_\.]+)');
      final RegExp dartPackage =
          RegExp(r"androidPackageName\s*=\s*'([^']+)'");

      final String? namespaceMatch = gradleNamespace.firstMatch(gradle)?.group(1);
      final String? appIdMatch = gradleAppId.firstMatch(gradle)?.group(1);
      final String? kotlinMatch = kotlinPackage.firstMatch(mainActivity)?.group(1);
      final String? dartMatch = dartPackage.firstMatch(googleConfig)?.group(1);

      expect(
        [namespaceMatch, appIdMatch, kotlinMatch, dartMatch],
        everyElement('com.zierch.expense_tracker'),
        reason:
            'SECURITY: package name must be identical in build.gradle.kts '
            '(namespace), build.gradle.kts (applicationId), MainActivity.kt '
            '(package), and google_config.dart (androidPackageName). Google Cloud '
            'Console binds an OAuth client to a package name + signing SHA-1; any '
            'mismatch produces clientConfigurationError at sign-in.',
      );
    });

    test('no com.example placeholder must remain in Gradle config', () {
      final String gradle = _kotlinCode(
        File('android/app/build.gradle.kts').readAsStringSync(),
      );

      expect(
        gradle,
        isNot(contains('com.example')),
        reason:
            'SECURITY: com.example is the Android Studio template default; any '
            'occurrence in build.gradle.kts means the package rename was incomplete '
            'and would cause OAuth sign-in to fail.',
      );
    });

    test('no com.example placeholder must remain in MainActivity', () {
      final String mainActivity = File(
              'android/app/src/main/kotlin/com/zierch/expense_tracker/MainActivity.kt')
          .readAsStringSync();

      expect(
        mainActivity,
        isNot(contains('com.example')),
        reason:
            'SECURITY: com.example is the Android Studio template default; if it '
            'appears in MainActivity.kt, the package rename was incomplete.',
      );
    });

    test('no com.example placeholder must remain in google_config.dart', () {
      final String googleConfig =
          File('lib/data/services/google_config.dart').readAsStringSync();

      expect(
        googleConfig,
        isNot(contains('com.example')),
        reason:
            'SECURITY: com.example is the template default; if it appears in '
            'google_config.dart, the package name is not yet configured correctly.',
      );
    });
  });

  group('OAuth scope and credentials', () {
    test('OAuth scope must be drive.file only', () {
      final String googleConfig =
          File('lib/data/services/google_config.dart').readAsStringSync();

      expect(
        googleConfig,
        stringContainsInOrder([
          'https://www.googleapis.com/auth/drive.file',
        ]),
        reason:
            'SECURITY: the declared OAuth scope must be '
            'https://www.googleapis.com/auth/drive.file (read/write only to files '
            'the app creates). A broader scope like auth/drive would grant access '
            'to the user\'s entire Drive and trigger Google\'s restricted-scope '
            'verification process.',
      );
    });

    test('the scopes sent to Google must be exactly the declared one', () {
      final String service =
          File('lib/data/services/google_drive_service.dart').readAsStringSync();

      // google_config.dart declaring a narrow scope proves nothing on its own. What
      // the user is actually asked to grant is whatever the service hands to the
      // SDK, so pin the declaration and every call site together.
      expect(
        service,
        matches(
          RegExp(r'_scopes\s*=\s*<String>\[\s*GoogleConfig\.driveFileScope\s*\]'),
        ),
        reason:
            'SECURITY: the scope list must be built from GoogleConfig.driveFileScope, '
            'so the scope that is requested is the scope that is declared.',
      );

      // Only *invocations* are inspected, which the leading dot identifies. The
      // service also declares its own private _authorizationHeaders() helper, and
      // matching every occurrence of these names counts that definition and its
      // call sites, which decide nothing about scope. The calls that matter are
      // the ones made on the authorization client.
      final RegExp scopeCalls = RegExp(
        r'\.(authorizationForScopes|authorizeScopes|authorizationHeaders)\(([^)]*)\)',
      );
      final Iterable<RegExpMatch> calls = scopeCalls.allMatches(service);

      expect(
        calls,
        isNotEmpty,
        reason:
            'SECURITY: google_drive_service.dart no longer calls a scope-taking '
            'method on the authorization client. If the Drive integration was '
            'rewritten, re-point this test at the new scope plumbing rather than '
            'deleting it.',
      );

      for (final RegExpMatch call in calls) {
        expect(
          call.group(2)!.contains('_scopes'),
          isTrue,
          reason:
              'SECURITY: every scope request must pass _scopes, but '
              '${call.group(0)} carries its own argument list. It could ask for a '
              'broader scope than google_config.dart declares while the check on '
              'the constant still passed, and users would be asked to grant more '
              'than the policy describes.',
        );
      }
    });

    test('no broader Drive scope may be embedded in lib/', () {
      final List<String> dartFiles = <String>[];
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .forEach((File f) => dartFiles.add(f.readAsStringSync()));
      final String allDart = dartFiles.join('\n');

      // Quoted literals only, so a comment is still allowed to name the scopes the
      // app deliberately avoids.
      for (final String scope in <String>[
        "'https://www.googleapis.com/auth/drive'",
        "'https://www.googleapis.com/auth/drive.readonly'",
        "'https://www.googleapis.com/auth/drive.appdata'",
        "'https://www.googleapis.com/auth/drive.metadata'",
        "'https://www.googleapis.com/auth/drive.metadata.readonly'",
        "'https://www.googleapis.com/auth/drive.photos.readonly'",
      ]) {
        expect(
          allDart,
          isNot(contains(scope)),
          reason:
              'SECURITY: $scope reaches beyond the files this app created. drive.file '
              'is the promise PRIVACY.md makes and the reason this app avoids '
              'Google\'s restricted-scope review; a broader scope would make that '
              'promise untrue.',
        );
      }
    });

    test('serverClientId must be the placeholder or a well-formed client ID',
        () {
      final String googleConfig =
          File('lib/data/services/google_config.dart').readAsStringSync();

      final RegExp clientId = RegExp(r"serverClientId\s*=\s*'([^']+)'");
      final String? match = clientId.firstMatch(googleConfig)?.group(1);

      expect(
        match,
        isNotNull,
        reason: 'GoogleConfig must declare serverClientId, even as a placeholder.',
      );

      // Committing the real client ID is intentional and not a defect: the APK
      // on the Releases page has to sign in for the people it is handed to, and
      // a client ID is a public identifier rather than a credential. What must
      // never appear is the *secret* printed next to it in the Console, which
      // is asserted separately below.
      if (match!.startsWith('PASTE_')) return;

      expect(
        match,
        endsWith('.apps.googleusercontent.com'),
        reason:
            'SECURITY: serverClientId must hold a *Web application* client ID, '
            'which ends in .apps.googleusercontent.com. An Android client ID, or '
            'a truncated paste, produces clientConfigurationError at sign-in.',
      );
      expect(
        match.length,
        greaterThan(40),
        reason:
            'GoogleConfig.serverClientId looks truncated; a real web client ID '
            'is around 70 characters long.',
      );
    });

    test('no client_secret may be hard-coded in lib/', () {
      final List<String> dartFiles = <String>[];
      final Directory libDir = Directory('lib');
      libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .forEach((File f) => dartFiles.add(f.readAsStringSync()));

      final String allDart = dartFiles.join('\n');

      expect(
        allDart,
        isNot(contains('client_secret')),
        reason:
            'SECURITY: this is a public client and must never embed an OAuth '
            'client_secret. The string "client_secret" must not appear anywhere '
            'in lib/.',
      );
    });
  });

  group('secret-shaped credentials in tracked files', () {
    test('no secret-shaped values may appear in tracked working tree or index', () {
      String root;
      try {
        root = _getGitRoot();
      } on _GitNotAvailableException {
        markTestSkipped('git is not available; cannot verify tracked file contents');
        return;
      }

      final List<String> workingTreeFindings = _findSecretsInWorkingTree(root);
      final List<String> indexFindings = _findSecretsInIndex(root);
      final List<String> allFindings = <String>[...workingTreeFindings, ...indexFindings];

      // Verify the scan actually looked at files (not a cwd/anchoring bug)
      final ProcessResult lsFiles = Process.runSync(
        'git',
        <String>['ls-files'],
        workingDirectory: root,
      );
      final List<String> trackedFiles =
          (lsFiles.stdout as String).split('\n').where((String f) => f.isNotEmpty).toList();

      expect(
        trackedFiles.length,
        greaterThan(20),
        reason:
            'the secret guard must not pass on an empty scan (anchoring/cwd bug)',
      );

      expect(
        allFindings,
        isEmpty,
        reason:
            'SECURITY: no credential-shaped value may be committed. Tracked files '
            'in working tree or staged in index must never contain: Google OAuth '
            'secrets (GOCSPX-*), API keys (AIza*), access tokens (ya29.*), refresh '
            'tokens (1//0*), or PEM private keys with body. Findings: $allFindings',
      );
    });

    test('scanner detects all secret patterns (with body) and rejects bare prose', () {
      // Control: prove the scanner detects every pattern.
      // Build fakes at runtime (no literal in source may match a pattern).

      final String fakeGoogleSecret = 'GOCSPX-${'A' * 24}';
      final String fakeApiKey = 'AIza${'B' * 24}';
      final String fakeAccessToken = 'ya29.${'C' * 24}';
      final String fakeRefreshToken = '1//0${'D' * 24}';
      // PEM with body: header + newline + base64 chars
      const String fakePemHeader = '-----BEGIN ' 'RSA ' 'PRIVATE KEY-----';
      final String fakePemWithBody = '$fakePemHeader\nMIIEpAIBAAKCAQEA${'X' * 30}';

      expect(_containsSecrets('secret: $fakeGoogleSecret'), isTrue,
          reason: 'SECURITY: scanner must detect GOCSPX-* pattern.');
      expect(_containsSecrets('secret: $fakeApiKey'), isTrue,
          reason: 'SECURITY: scanner must detect AIza* pattern.');
      expect(_containsSecrets('secret: $fakeAccessToken'), isTrue,
          reason: 'SECURITY: scanner must detect ya29.* pattern.');
      expect(_containsSecrets('secret: $fakeRefreshToken'), isTrue,
          reason: 'SECURITY: scanner must detect 1//0* pattern.');
      expect(_containsSecrets(fakePemWithBody), isTrue,
          reason:
              'SECURITY: scanner must detect PEM private keys (header + body).');

      // Negative cases: documentation should not trigger
      expect(_containsSecrets('see the GOCSPX- and AIza notes in the guide'), isFalse,
          reason:
              'SECURITY: scanner must NOT match partial credentials in prose; '
              'only complete value shapes.');
      expect(_containsSecrets('-----BEGIN PRIVATE KEY-----'), isFalse,
          reason:
              'SECURITY: scanner must NOT match bare PEM headers in prose; '
              'body (base64) is required.');

      // Bare DSA and PGP headers (no body) must also not trigger
      const String bareDsaHeader = '-----BEGIN ' 'DSA ' 'PRIVATE KEY-----';
      const String barePgpHeader = '-----BEGIN ' 'PGP ' 'PRIVATE KEY BLOCK-----';
      expect(_containsSecrets(bareDsaHeader), isFalse,
          reason: 'SECURITY: bare DSA header without body must not match.');
      expect(_containsSecrets(barePgpHeader), isFalse,
          reason: 'SECURITY: bare PGP header without body must not match.');

      expect(_containsSecrets('amount = 12000'), isFalse,
          reason: 'SECURITY: scanner must NOT match normal code.');

      // Control: findings detection as used in actual scans
      expect(_findSecretLineNumbers('secret: $fakeGoogleSecret'), isNotEmpty,
          reason: 'line-number scanner must find GOCSPX-*');
      expect(_findSecretLineNumbers('-----BEGIN PRIVATE KEY-----'), isEmpty,
          reason: 'line-number scanner must reject bare PEM header');
      expect(_findSecretLineNumbers(bareDsaHeader), isEmpty,
          reason: 'line-number scanner must reject bare DSA header');
      expect(_findSecretLineNumbers(barePgpHeader), isEmpty,
          reason: 'line-number scanner must reject bare PGP header');
      expect(_findSecretLineNumbers(fakePemWithBody), isNotEmpty,
          reason: 'line-number scanner must find PEM+body');
    });

    test('staged-then-deleted files in index are detected (GOCSPX and PEM)', () {
      try {
        _requireGitBinary();
      } on _GitNotAvailableException {
        markTestSkipped('git is not available');
        return;
      }

      // Create a scratch repo in temp to isolate the test
      final Directory scratchDir = Directory(p.join(Directory.systemTemp.path, 'expense-tracker-secret-guard-${DateTime.now().millisecondsSinceEpoch}'));
      scratchDir.createSync();

      try {
        // Init scratch repo
        final ProcessResult gitInit = Process.runSync(
          'git',
          <String>['init'],
          workingDirectory: scratchDir.path,
        );
        expect(gitInit.exitCode, 0, reason: 'git init failed');

        // Test case A: staged-then-deleted GOCSPX secret
        final String fakeGocspxSecret = 'GOCSPX-${'Y' * 24}';
        final File probeFileA = File(p.join(scratchDir.path, 'secret_gocspx.txt'));
        probeFileA.writeAsStringSync('config: $fakeGocspxSecret\n');

        final ProcessResult gitAddA = Process.runSync(
          'git',
          <String>['add', 'secret_gocspx.txt'],
          workingDirectory: scratchDir.path,
        );
        expect(gitAddA.exitCode, 0, reason: 'git add secret_gocspx.txt failed');

        probeFileA.deleteSync();

        // Test case B: staged-then-deleted PEM secret with body
        const String pemHeader = '-----BEGIN ' 'RSA ' 'PRIVATE KEY-----';
        final String fakePemSecret = '$pemHeader\nMIIEpAIBAAKCAQEA${'Z' * 30}\n';
        final File probeFileB = File(p.join(scratchDir.path, 'secret_pem.txt'));
        probeFileB.writeAsStringSync(fakePemSecret);

        final ProcessResult gitAddB = Process.runSync(
          'git',
          <String>['add', 'secret_pem.txt'],
          workingDirectory: scratchDir.path,
        );
        expect(gitAddB.exitCode, 0, reason: 'git add secret_pem.txt failed');

        probeFileB.deleteSync();

        // Test case C: staged prose (bare PEM header) that should NOT be flagged
        final File probeFileC = File(p.join(scratchDir.path, 'prose.txt'));
        probeFileC.writeAsStringSync('See the -----BEGIN PRIVATE KEY----- format in the docs.\n');

        final ProcessResult gitAddC = Process.runSync(
          'git',
          <String>['add', 'prose.txt'],
          workingDirectory: scratchDir.path,
        );
        expect(gitAddC.exitCode, 0, reason: 'git add prose.txt failed');

        probeFileC.deleteSync();

        // Test case D: staged-then-deleted binary file with secret-shaped bytes.
        // Pins end-to-end binary detection: the prefilter must return binary entries
        // and the confirmation must decode bytes tolerantly. Note: `git grep -l`
        // lists binary matches with or without `-a` (verified by experiment), so `-a`
        // documents text-mode intent rather than changing behaviour here. The
        // working-tree scan cannot help: the file is deleted.
        final String fakeBinarySecret = 'GOCSPX-${'B' * 24}';
        final File probeBinary = File(p.join(scratchDir.path, 'binary.dat'));
        probeBinary.writeAsBytesSync(
            utf8.encode('data: ') + utf8.encode(fakeBinarySecret) + utf8.encode('\x00\xFF'));

        final ProcessResult gitAddBin = Process.runSync(
          'git',
          <String>['add', 'binary.dat'],
          workingDirectory: scratchDir.path,
        );
        expect(gitAddBin.exitCode, 0, reason: 'git add binary.dat failed');

        probeBinary.deleteSync();

        // Index scan must report both GOCSPX and PEM but not bare prose
        final List<String> indexFindings = _findSecretsInIndex(scratchDir.path);
        final List<String> workingTreeFindings = _findSecretsInWorkingTree(scratchDir.path);

        expect(indexFindings, contains(matches(RegExp(r'secret_gocspx\.txt.*staged'))),
            reason:
                'SECURITY: index scan must detect staged GOCSPX secret even after deletion.');
        expect(indexFindings, contains(matches(RegExp(r'secret_pem\.txt.*staged'))),
            reason:
                'SECURITY: index scan must detect staged PEM secret (with body) even after deletion.');
        expect(indexFindings, contains(matches(RegExp(r'binary\.dat.*staged'))),
            reason:
                'SECURITY: index scan must detect staged secret in binary (byte-shaped) even after deletion. '
                'This is what -l guarantees for binary entries; -a keeps the prefilter explicitly text-mode.');
        expect(indexFindings, isNot(contains(matches(RegExp(r'prose\.txt')))),
            reason:
                'SECURITY: index scan must NOT flag bare PEM headers in prose.');

        expect(workingTreeFindings, isEmpty,
            reason:
                'SECURITY: working-tree scan correctly reports nothing for deleted files; '
                'index scan covers the staged state.');
      } finally {
        scratchDir.deleteSync(recursive: true);
      }
    });

    test('unstaged non-ASCII filename with secret is detected by working-tree scan', () {
      try {
        _requireGitBinary();
      } on _GitNotAvailableException {
        markTestSkipped('git is not available');
        return;
      }

      // M-A regression: git ls-files without -z produces C-quoted paths like "caf\303\251.txt"
      // which File(...) cannot resolve. This control ensures the guard fails if -z is dropped.
      final Directory scratchDir = Directory(p.join(Directory.systemTemp.path, 'expense-tracker-secret-guard-ma-${DateTime.now().millisecondsSinceEpoch}'));
      scratchDir.createSync();

      try {
        // Init scratch repo
        final ProcessResult gitInit = Process.runSync(
          'git',
          <String>['init'],
          workingDirectory: scratchDir.path,
        );
        expect(gitInit.exitCode, 0, reason: 'git init failed');

        // Create file with non-ASCII name; stage clean content
        const String nonAsciiName = 'zz caf\u00e9.txt';
        final File nonAsciiFile = File(p.join(scratchDir.path, nonAsciiName));
        nonAsciiFile.writeAsStringSync('clean content\n');

        final ProcessResult gitAdd = Process.runSync(
          'git',
          <String>['add', nonAsciiName],
          workingDirectory: scratchDir.path,
        );
        expect(gitAdd.exitCode, 0, reason: 'git add failed');

        // Append secret to working-tree file (unstaged)
        final String fakeSecret = 'GOCSPX-${'M' * 24}';
        nonAsciiFile.writeAsStringSync('clean content\n' 'leak: $fakeSecret\n', mode: FileMode.append);

        // Working-tree scan MUST resolve the non-ASCII path and detect the unstaged secret.
        // This test fails if `-z` is dropped from git ls-files, because git would emit
        // C-quoted `"zz caf\303\251.txt"` and the path would not resolve.
        final List<String> workingTreeFindings = _findSecretsInWorkingTree(scratchDir.path);

        expect(workingTreeFindings, contains(matches(RegExp(r'caf.*\.txt:[23]'))),
            reason:
                'SECURITY: working-tree scan must resolve non-ASCII filenames and report secrets. '
                'This requires git ls-files -z (NUL-delimited) to avoid C-quoting. '
                'If this test fails, -z was dropped from the git ls-files call.');
      } finally {
        scratchDir.deleteSync(recursive: true);
      }
    });

    test('no signing keystores or key.properties are git-tracked', () {
      String root;
      try {
        root = _getGitRoot();
      } on _GitNotAvailableException {
        markTestSkipped('git is not available; cannot verify tracked files');
        return;
      }

      final ProcessResult lsFiles;
      try {
        lsFiles = Process.runSync(
          'git',
          <String>['ls-files', '-z'],
          workingDirectory: root,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
      } on ProcessException {
        throw StateError('git ls-files failed');
      }

      if (lsFiles.exitCode != 0) {
        throw StateError('git ls-files exited ${lsFiles.exitCode}');
      }

      // Split on NUL bytes (result of -z flag) for proper UTF-8 path handling
      final List<String> trackedFiles =
          (lsFiles.stdout as String).split('\x00').where((String f) => f.isNotEmpty).toList();

      expect(trackedFiles.length, greaterThan(20),
          reason: 'scan must include files from repo root (not a cwd bug)');

      for (final String file in trackedFiles) {
        // Exact path match: must be 'android/key.properties', not 'my-key.properties'
        expect(
          file,
          isNot(equalsIgnoringCase('android/key.properties')),
          reason:
              'SECURITY: android/key.properties must never be committed. '
              'It contains the release signing password and is git-ignored. '
              '(android/key.properties.example is allowed as a template.)',
        );

        expect(
          file,
          isNot(endsWith('.jks')),
          reason:
              'SECURITY: *.jks keystores must never be committed; they contain '
              'the release signing key material and must stay local only.',
        );

        expect(
          file,
          isNot(endsWith('.keystore')),
          reason:
              'SECURITY: *.keystore keystores must never be committed; they contain '
              'the release signing key material and must stay local only.',
        );
      }
    });
  });

  // The Gradle assertions read comments, and build.gradle.kts really does contain
  // the construct that _kotlinCode's doc comment names as its blind spot:
  // `"android/key.properties has no value for: ${blank.joinToString(", ")}."`. The
  // token-forbidding check therefore asks two classifiers with opposite blind spots,
  // so neither a character-level nor a line-level mistake can hide a defect alone.
  group('_codeLines comment stripping', () {
    test('is not fooled by a string template holding a comment marker', () {
      const String source = r'''
        val msg = "count ${a("x//y")}"
        signingConfig = signingConfigs["debug"]
        // signingConfig = signingConfigs["debug"]
      ''';

      final List<String> offenders = _codeLines(source)
          .where((String line) => line.contains('"debug"'))
          .map((String line) => line.trim())
          .toList();

      expect(offenders, hasLength(1));
      expect(offenders.single, contains('signingConfigs["debug"]'));
    });

    test('skips full-line comments and block comments', () {
      const String source = '''
        // getByName("debug")
        val live = 1
        /* getByName("debug")
           still commented */
        val alsoLive = 2
      ''';

      final List<String> code = _codeLines(source);

      expect(code.join('\n'), isNot(contains('debug')));
      expect(code.join('\n'), contains('val live = 1'));
      expect(code.join('\n'), contains('val alsoLive = 2'));
    });
  });

  // The token-forbidding check asks two classifiers because they fail in opposite
  // directions. Each of the first three tests feeds it a source that ONE of them
  // misses, so dropping either half of the pair turns exactly one of these red.
  group('debug signing detection', () {
    test('catches a token behind a leading block comment', () {
      // The line view discards this line whole: its left edge is a block comment, so
      // the line is dropped before the closing marker can matter. The character view
      // keeps whatever follows the closing marker, so the pair still sees it.
      const String source =
          '/* release */ signingConfig = signingConfigs["debug"]\n';

      expect(_debugSigningOffenders(source), hasLength(1));
    });

    test('catches a token after a block comment opened inside a string', () {
      // The line view turns block-comment mode on here and then swallows the real
      // assignment below it. The character view understands triple-quoted strings and
      // does not, so the pair still sees it.
      const String source = r'''
        val msg = """
        /* x
        """
        signingConfig = signingConfigs["debug"]
      ''';

      expect(_debugSigningOffenders(source), hasLength(1));
    });

    test('catches a token a string template hides from the character view', () {
      // The reverse case, and the one that made this pair necessary: the quote inside
      // the template ends the string early, the `//` inside it then starts a comment,
      // and the assignment is stripped away. The line view never looks inside the
      // line, so it still sees it. Before the pair existed, this source passed the
      // whole suite and a debug-signed release could have shipped.
      const String source =
          'val demo = "\${listOf("a//b")}"; signingConfig = signingConfigs["debug"]\n';

      expect(_debugSigningOffenders(source), hasLength(1));
    });

    test('says nothing when the only mention is commented out', () {
      const String source =
          '// signingConfig = signingConfigs["debug"]\nval a = 1\n';

      expect(_debugSigningOffenders(source), isEmpty);
    });
  });

  // The Gradle assertions read a file this project writes comments into, and one
  // of those comments names the very string that is being forbidden. The
  // stripping helper is therefore load-bearing, so it is tested like any other
  // logic rather than trusted.
  group('_kotlinCode comment stripping', () {
    test('removes line and block comments while keeping the code', () {
      const String source = r'''
        val a = 1 // getByName("debug")
        /* getByName("debug") */
        val b = 2
      ''';

      final String code = _kotlinCode(source);

      expect(code, isNot(contains('getByName')));
      expect(code, contains('val a = 1'));
      expect(code, contains('val b = 2'));
    });

    test('keeps comment markers that live inside strings', () {
      const String source = r'''
        val url = "https://example.com/x"
        val raw = """
          // not a comment
          val inside = "quoted"
        """
        val after = 3
      ''';

      final String code = _kotlinCode(source);

      expect(code, contains('https://example.com/x'));
      expect(code, contains('// not a comment'));
      expect(code, contains('val after = 3'));
    });

    test('an escaped quote does not terminate a string', () {
      const String source = r'''
        val s = "a \" // b" // trailing
        val after = 4
      ''';

      final String code = _kotlinCode(source);

      expect(code, contains(r'"a \" // b"'));
      expect(code, contains('val after = 4'));
      expect(code, isNot(contains('trailing')));
    });
  });
}

/// Returns the contents of the first `<name> ... </name>` pair in [xml], or an
/// empty string when that section is absent.
///
/// Section-scoped assertions matter here: searching the whole document would
/// happily match a rule that lives in the *other* section.
String _xmlSection(String xml, String name) {
  final int start = xml.indexOf('<$name>');
  final int end = xml.indexOf('</$name>');
  if (start < 0 || end < start) return '';
  return xml.substring(start, end);
}

/// Returns [xml] with its comment blocks removed.
///
/// The rules file documents its own decisions in XML comments, and an assertion
/// about what the file *declares* must not be satisfiable by prose: a comment can
/// name an element that is not there, or hide one that is.
String _xmlElements(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Returns the `<name>` section of the data extraction rules, comments removed.
String _rulesSection(String name) =>
    _xmlSection(_xmlElements(File(_rulesPath).readAsStringSync()), name);

/// Returns the lines of [source] that are not inside a comment.
///
/// A line-oriented view. A trailing comment on a line of code keeps that line, so a
/// mention there is flagged as well: this helper exists to forbid a token, and a
/// false alarm is cheaper than a missed signing regression.
///
/// This is not a lexer and has blind spots of its own, which is why
/// [_debugSigningOffenders] does not rely on it alone:
///
///   * A line whose left edge is a block comment is dropped whole, even when live
///     code follows the closing marker on that same line.
///   * A block comment opened inside a string turns comment mode on and swallows
///     the real lines after it.
///
/// Both directions are pinned by tests in this file.
List<String> _codeLines(String source) {
  final List<String> code = <String>[];
  bool inBlockComment = false;

  for (final String line in source.split('\n')) {
    final String trimmed = line.trimLeft();

    if (inBlockComment) {
      if (trimmed.contains('*/')) inBlockComment = false;
      continue;
    }
    if (trimmed.startsWith('/*')) {
      if (!trimmed.contains('*/')) inBlockComment = true;
      continue;
    }
    if (trimmed.startsWith('//')) continue;

    code.add(line);
  }

  return code;
}

/// Returns every way [source] breaks the rule that no debug signing config may be
/// named. An empty list means the rule holds.
///
/// Deliberately asks two classifiers, because they fail in opposite directions and
/// a token has to survive both to be ruled out:
///
///   * [_codeLines] drops a live line whose left edge is a block comment, and can
///     swallow the lines after a block comment opened inside a string.
///   * [_kotlinCode] can hide a token behind a string template holding a quote,
///     which build.gradle.kts really does contain.
List<String> _debugSigningOffenders(String source) {
  final String withoutComments = _kotlinCode(source);

  return <String>[
    ..._codeLines(source)
        .where((String line) => line.contains('"debug"'))
        .map((String line) => line.trim()),
    ...withoutComments
        .split('\n')
        .where((String line) => line.contains('"debug"'))
        .map((String line) => 'survived comment stripping: ${line.trim()}'),
  ];
}


/// Returns [source] with Kotlin comments, and their contents, removed.
///
/// Assertions about this project's Gradle config have to test code rather than
/// prose: the header of build.gradle.kts deliberately names the template line it
/// refuses to copy, so a check run against the raw file text fails on the file's
/// own explanation.
///
/// This is not a Kotlin lexer. It understands line comments, block comments,
/// escaped quotes and triple-quoted strings, which is what build.gradle.kts
/// contains. A string template holding a quote inside a `"${...}"` expression can
/// still mislead the string tracking, which is why it is used only where stripping
/// too much fails the test: every call site here asserts that something *is*
/// present. The one check that forbids a token, where stripping too much would
/// hide a defect instead of reporting one, classifies lines with [_codeLines].
String _kotlinCode(String source) {
  final StringBuffer out = StringBuffer();
  bool inLineComment = false;
  bool inBlockComment = false;
  bool inString = false;
  bool inRawString = false;

  for (int i = 0; i < source.length; i++) {
    final String c = source[i];
    final String next = i + 1 < source.length ? source[i + 1] : '';
    final String next2 = i + 2 < source.length ? source[i + 2] : '';

    if (inLineComment) {
      if (c == '\n') {
        inLineComment = false;
        out.write(c);
      }
      continue;
    }

    if (inBlockComment) {
      if (c == '*' && next == '/') {
        inBlockComment = false;
        i++;
      }
      continue;
    }

    if (inRawString) {
      // A triple-quoted string takes no escape sequences, so only the closing
      // """ ends one; quotes inside it are ordinary characters.
      out.write(c);
      if (c == '"' && next == '"' && next2 == '"') {
        out.write('""');
        i += 2;
        inRawString = false;
      }
      continue;
    }

    if (inString) {
      out.write(c);
      if (c == '\\') {
        if (next.isNotEmpty) {
          out.write(next);
          i++;
        }
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }

    if (c == '"' && next == '"' && next2 == '"') {
      out.write('"""');
      i += 2;
      inRawString = true;
      continue;
    }

    if (c == '/' && next == '/') {
      inLineComment = true;
      i++;
      continue;
    }

    if (c == '/' && next == '*') {
      inBlockComment = true;
      i++;
      continue;
    }

    if (c == '"') {
      inString = true;
    }

    out.write(c);
  }

  return out.toString();
}

/// Probes for git binary availability; throws if not found.
/// Used by tests that only need to confirm git is runnable (not a full work-tree check).
void _requireGitBinary() {
  try {
    Process.runSync('git', <String>['--version'],
        stdoutEncoding: utf8, stderrEncoding: utf8);
  } on ProcessException {
    throw const _GitNotAvailableException('git binary not available');
  }
}

/// Returns git repo root or throws distinct errors for different failure modes.
///
/// Throws `_GitNotAvailableException` if git binary is missing (host issue → may skip).
/// Throws `StateError` if not a work tree (broken premise → must fail loudly).
String _getGitRoot() {
  final ProcessResult root;
  try {
    root = Process.runSync('git', <String>['rev-parse', '--show-toplevel'],
        stdoutEncoding: utf8, stderrEncoding: utf8);
  } on ProcessException catch (e) {
    // Git binary not available: host property, not a code defect.
    throw _GitNotAvailableException('git binary not available: $e');
  }

  if (root.exitCode != 0) {
    // Not a git work tree: broken premise for the guard, must fail loudly.
    throw StateError(
        'SECURITY GUARD BROKEN: could not resolve a git work tree. '
        'The secret guard assumes a git work tree and cannot run outside one. '
        'stderr: ${root.stderr}');
  }

  return (root.stdout as String).trim();
}

/// Returns lines from [content] that match secret-shaped value patterns, with line numbers.
///
/// Matches literal credential formats that would be dangerous if committed:
/// - GOCSPX-[20+ chars] (Google OAuth client secret)
/// - AIza[20+ chars] (Google API key)
/// - ya29.[20+ chars] (Google access token)
/// - 1//0[20+ chars] (Google refresh token)
/// - -----BEGIN...PRIVATE KEY----- with body (PEM-format private keys, including DSA and PGP)
///
/// Returns list where each match identifies its line (1-indexed).
/// For multi-line PEM patterns, returns the header line number.
/// Does not match documentation mentioning these names without complete values.
List<int> _findSecretLineNumbers(String content) {
  final Set<int> foundLines = <int>{};
  final List<String> lines = content.split('\n');
  final List<RegExp> singleLinePatterns = <RegExp>[
    RegExp(r'GOCSPX-[A-Za-z0-9_-]{20,}'),
    RegExp(r'AIza[0-9A-Za-z_-]{20,}'),
    RegExp(r'ya29\.[A-Za-z0-9_-]{20,}'),
    RegExp(r'1//0[A-Za-z0-9_-]{20,}'),
  ];

  // Check single-line patterns
  for (int i = 0; i < lines.length; i++) {
    for (final RegExp pattern in singleLinePatterns) {
      if (pattern.hasMatch(lines[i])) {
        foundLines.add(i + 1);
        break;
      }
    }
  }

  // Check multi-line PEM patterns: header + body
  // RSA, EC, OpenSSH, DSA standard formats + PGP block format
  final RegExp pemPattern = RegExp(
      r'-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY(?: BLOCK)?-----[\r\n]+[A-Za-z0-9+/=\-]{20,}',
      multiLine: true);

  if (pemPattern.hasMatch(content)) {
    // Find the line with the header and report it
    for (int i = 0; i < lines.length; i++) {
      if ((lines[i].contains('-----BEGIN') && lines[i].contains('PRIVATE KEY')) ||
          (lines[i].contains('-----BEGIN') && lines[i].contains('PRIVATE KEY BLOCK'))) {
        foundLines.add(i + 1);
        break;
      }
    }
  }

  return foundLines.toList()..sort();
}

// Files exceeding size cap (8 MB) are reported as findings (loud failure via expect).
// Read errors on existing files throw loudly. Keep the cap small to avoid buffering huge blobs.
const int _fileSizeCap = 8 * 1024 * 1024;

/// Returns list of findings as `'<path>:<linenum>'` from working tree.
///
/// Scans only tracked files using `git ls-files -z` for proper UTF-8 path handling.
/// Reports findings with exact line numbers.
/// Files exceeding size cap are reported as capped findings.
/// Files that exist but cannot be read throw loudly (could hide secrets).
List<String> _findSecretsInWorkingTree(String gitRoot) {
  final ProcessResult lsFiles;
  try {
    lsFiles = Process.runSync(
      'git',
      <String>['ls-files', '-z'],
      workingDirectory: gitRoot,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException {
    throw StateError('git ls-files failed');
  }

  if (lsFiles.exitCode != 0) {
    throw StateError('git ls-files exited ${lsFiles.exitCode}');
  }

  final List<String> findings = <String>[];
  // Split on NUL bytes (result of -z flag) for proper UTF-8 path handling
  final List<String> files =
      (lsFiles.stdout as String).split('\x00').where((String f) => f.isNotEmpty).toList();

  for (final String filePath in files) {
    final File file = File(p.join(gitRoot, filePath));
    if (!file.existsSync()) continue;

    String content;
    try {
      final List<int> bytes = file.readAsBytesSync();
      if (bytes.length > _fileSizeCap) {
        // Unscanned file (size cap): fail loudly
        findings.add('$filePath (file exceeds 8 MB size cap; unscanned)');
        continue;
      }
      content = utf8.decode(bytes, allowMalformed: true);
    } on FileSystemException catch (e) {
      // File exists but cannot be read: fail loudly (could hide secrets).
      throw StateError(
          'SECURITY GUARD FAILURE: tracked file $filePath exists but cannot be read. '
          'A secret could be hidden here. Error: $e');
    }

    final List<int> lineNumbers = _findSecretLineNumbers(content);
    for (final int lineNum in lineNumbers) {
      findings.add('$filePath:$lineNum');
    }
  }

  return findings;
}

/// Returns list of findings as `'<path> (staged)'` from git index.
///
/// Uses `git grep --cached -a -z` (-z for NUL-delimited output; -a marks the
/// prefilter as explicitly text-mode — `-l` lists binary matches either way)
/// as prefilter, then confirms with strict scanner by reading index content via `git show ":<path>"`.
/// Handles UTF-8 encoding explicitly on all git calls to avoid mangling non-ASCII file names.
/// Files exceeding size cap (8 MB) are reported as capped; an unscanned file fails loudly.
List<String> _findSecretsInIndex(String gitRoot) {
  // Coarse prefilter alternation (matches candidates)
  const String patternAlt = r'(GOCSPX-[A-Za-z0-9_-]{20,}|'
      r'AIza[0-9A-Za-z_-]{20,}|'
      r'ya29\.[A-Za-z0-9_-]{20,}|'
      r'1//0[A-Za-z0-9_-]{20,}|'
      r'-----BEGIN.*(PRIVATE KEY|PRIVATE KEY BLOCK))';

  final ProcessResult grep;
  try {
    grep = Process.runSync(
      'git',
      <String>['grep', '--cached', '-a', '-z', '-l', '-E', patternAlt],
      workingDirectory: gitRoot,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException {
    throw StateError('git grep --cached failed');
  }

  // Exit 0: matches found. Exit 1: no matches (not an error).
  if (grep.exitCode == 1) return <String>[];
  if (grep.exitCode != 0) {
    throw StateError('git grep --cached exited ${grep.exitCode}: ${grep.stderr}');
  }

  // Split on NUL bytes (result of -z flag) to get real paths without quoting
  final List<String> candidates =
      (grep.stdout as String).split('\x00').where((String f) => f.isNotEmpty).toList();

  final List<String> confirmed = <String>[];

  // Confirm each candidate with strict scanner
  for (final String candidatePath in candidates) {
    final ProcessResult show;
    try {
      // Explicitly pass stdoutEncoding: null to get raw bytes; size-cap check + allowMalformed decode
      show = Process.runSync(
        'git',
        <String>['show', ':$candidatePath'],
        workingDirectory: gitRoot,
        stdoutEncoding: null,
        stderrEncoding: utf8,
      );
    } on ProcessException {
      // Can't read from index: fail loudly (candidate was found but unreachable).
      throw StateError(
          'SECURITY GUARD FAILURE: index candidate $candidatePath matched prefilter '
          'but cannot be read via git show. This should not happen; git state is corrupt?');
    }

    if (show.exitCode != 0) {
      throw StateError(
          'SECURITY GUARD FAILURE: git show :$candidatePath exited ${show.exitCode}. '
          'Candidate was flagged but is now unreachable.');
    }

    String content;
    try {
      final List<int> bytes = show.stdout as List<int>;
      
      if (bytes.length > _fileSizeCap) {
        // Unscanned file (size cap): fail loudly
        confirmed.add('$candidatePath (staged, exceeds 8 MB size cap; unscanned)');
        continue;
      }
      content = utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      throw StateError('Failed to decode index content for $candidatePath: $e');
    }

    final List<int> lineNumbers = _findSecretLineNumbers(content);

    if (lineNumbers.isNotEmpty) {
      confirmed.add('$candidatePath (staged)');
    }
  }

  return confirmed;
}

/// Legacy function for unit testing scanner logic.
/// Returns whether [content] contains any secret-shaped values (for unit tests only).
bool _containsSecrets(String content) => _findSecretLineNumbers(content).isNotEmpty;


// Security invariants for the release build and deployment.
//
// This app is published as a shared APK with personal financial records
// stored on-device. These tests lock in decisions that a future contributor
// could silently break, causing users to lose data or exposing backups.
//
// Read files from disk and assert that each invariant still holds.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('release build signing', () {
    test(
      'release build type must not fall back to debug keystore',
      () {
        final String gradle =
            File('android/app/build.gradle.kts').readAsStringSync();

        // The Flutter template ships `signingConfig = signingConfigs.getByName("debug")`
        // for release builds. Removing that line is what closes the hole: a debug-signed
        // APK is per-machine and recreatable, so a rebuild from anywhere else forces
        // every user to uninstall, deleting their financial database in the process.
        //
        // Asserted across the whole file rather than as a substring *sequence*, because
        // a sequence check also passes once the surrounding lines are reordered -- which
        // is exactly how this regression would arrive. Nothing here has a legitimate
        // reason to name the debug signing config: the `profile` build type that Flutter
        // adds inherits it implicitly.
        expect(
          gradle,
          isNot(contains('getByName("debug")')),
          reason:
              'SECURITY: nothing in build.gradle.kts may reference the debug signing '
              'config. If release used it, the shared APK would be signed with a '
              'per-machine keystore, so rebuilding anywhere else would force every '
              'user to uninstall, which deletes their financial database.',
        );
      },
    );

    test('release signing must load credentials from key.properties', () {
      final String gradle =
          File('android/app/build.gradle.kts').readAsStringSync();

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

      if (!Directory('.git').existsSync()) return;

      // Exit 0 means git will ignore the path. Exit 1 means it will not, which
      // covers both "untracked and unignored" and "already tracked", since
      // ignore rules never apply to a file git already tracks.
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
        isNot(1),
        reason:
            'SECURITY: git does not ignore android/key.properties, so the '
            'signing keystore password can be committed by accident.',
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
    test('release signing must also be enforced on the packaging task', () {
      final String gradle =
          File('android/app/build.gradle.kts').readAsStringSync();

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
    });
  });

  group('auto backup and device-to-device transfer', () {
    test('AndroidManifest must disable auto backup', () {
      final String manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      expect(
        manifest,
        stringContainsInOrder(['android:allowBackup="false"']),
        reason:
            'SECURITY: AndroidManifest must set android:allowBackup="false" to '
            'prevent Android from automatically backing up the SQLite database '
            'to Google Drive without user consent. The app exposes backup only '
            'through an explicit "Backup" button.',
      );
    });

    test('data_extraction_rules must exclude every domain from cloud-backup',
        () {
      final String cloudBackup = _xmlSection(
        File('android/app/src/main/res/xml/data_extraction_rules.xml')
            .readAsStringSync(),
        'cloud-backup',
      );

      expect(
        cloudBackup,
        isNotEmpty,
        reason:
            'SECURITY: data_extraction_rules.xml must contain a <cloud-backup> '
            'section. An absent section does not mean "nothing is backed up": '
            'Google documents that a missing section leaves that mode fully '
            'enabled.',
      );
      for (final String domain in <String>['root', 'database']) {
        expect(
          cloudBackup,
          contains('exclude domain="$domain"'),
          reason:
              'SECURITY: the cloud-backup section must exclude domain="$domain". '
              'This is asserted per section on purpose: a check that searched the '
              'whole file would also be satisfied by the device-transfer section, '
              'so deleting an exclusion from one section while the other still '
              'had it would silently pass. The database domain is the SQLite file '
              'holding the user\'s financial records.',
        );
      }
    });

    test(
        'data_extraction_rules must exclude every domain from device-transfer',
        () {
      final String deviceTransfer = _xmlSection(
        File('android/app/src/main/res/xml/data_extraction_rules.xml')
            .readAsStringSync(),
        'device-transfer',
      );

      expect(
        deviceTransfer,
        isNotEmpty,
        reason:
            'SECURITY: data_extraction_rules.xml must contain a <device-transfer> '
            'section, because Google documents that on Android 12+ on some '
            'manufacturers\' devices android:allowBackup="false" stops cloud '
            'backup but still permits device-to-device transfer.',
      );
      for (final String domain in <String>['root', 'database']) {
        expect(
          deviceTransfer,
          contains('exclude domain="$domain"'),
          reason:
              'SECURITY: the device-transfer section must exclude domain="$domain"; '
              'this is the path that allowBackup alone leaves open on Android 12+.',
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
      final String gradle =
          File('android/app/build.gradle.kts').readAsStringSync();

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

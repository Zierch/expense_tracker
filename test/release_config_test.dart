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
        expect(
          gradle,
          isNot(
            stringContainsInOrder([
              'buildTypes',
              'release',
              'signingConfig = signingConfigs.getByName("debug")',
            ]),
          ),
          reason:
              'SECURITY: release build type must NOT assign signingConfig = '
              'signingConfigs.getByName("debug"), because that would sign the '
              'shared APK with the debug keystore, forcing users to uninstall on '
              'any rebuild from a different machine, which deletes their financial '
              'database.',
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

    test('key.properties must be git-ignored and not committed', () {
      expect(
        File('android/key.properties').existsSync(),
        isFalse,
        reason:
            'SECURITY: android/key.properties (containing the signing keystore '
            'password) must never be committed; it is git-ignored and must stay '
            'on disk only on machines that build releases.',
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

    test('data_extraction_rules must exclude root domain from cloud-backup',
        () {
      final String rules =
          File('android/app/src/main/res/xml/data_extraction_rules.xml')
              .readAsStringSync();

      expect(
        rules,
        stringContainsInOrder([
          '<cloud-backup>',
          'exclude domain="root"',
        ]),
        reason:
            'SECURITY: data_extraction_rules.xml must have a cloud-backup section '
            'that excludes domain="root". On Android 12+, allowBackup=false may '
            'still leave cloud backup enabled on some devices, so this section '
            'closes that path.',
      );
    });

    test('data_extraction_rules must exclude database domain from cloud-backup',
        () {
      final String rules =
          File('android/app/src/main/res/xml/data_extraction_rules.xml')
              .readAsStringSync();

      expect(
        rules,
        stringContainsInOrder([
          '<cloud-backup>',
          'exclude domain="database"',
        ]),
        reason:
            'SECURITY: data_extraction_rules.xml cloud-backup section must '
            'exclude domain="database" to block backup of the SQLite database.',
      );
    });

    test(
      'data_extraction_rules must exclude root domain from device-transfer',
      () {
        final String rules =
            File('android/app/src/main/res/xml/data_extraction_rules.xml')
                .readAsStringSync();

        expect(
          rules,
          stringContainsInOrder([
            '<device-transfer>',
            'exclude domain="root"',
          ]),
          reason:
              'SECURITY: data_extraction_rules.xml must have a device-transfer '
              'section that excludes domain="root". Device-to-device transfer is '
              'an Android 12+ feature that can leave databases accessible even '
              'when allowBackup=false; this section blocks that path.',
        );
      },
    );

    test('data_extraction_rules must exclude database domain from device-transfer',
        () {
      final String rules =
          File('android/app/src/main/res/xml/data_extraction_rules.xml')
              .readAsStringSync();

      expect(
        rules,
        stringContainsInOrder([
          '<device-transfer>',
          'exclude domain="database"',
        ]),
        reason:
            'SECURITY: data_extraction_rules.xml device-transfer section must '
            'exclude domain="database" to block transfer of the SQLite database.',
      );
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

    test('serverClientId must remain the placeholder, not a real client ID',
        () {
      final String googleConfig =
          File('lib/data/services/google_config.dart').readAsStringSync();

      // A real web client ID is roughly 70 chars and ends with
      // .apps.googleusercontent.com. The placeholder is much shorter.
      final RegExp clientId = RegExp(
          r"serverClientId\s*=\s*'([^']+)'");
      final String? match = clientId.firstMatch(googleConfig)?.group(1);

      expect(
        match,
        startsWith('PASTE_'),
        reason:
            'SECURITY: GoogleConfig.serverClientId must not contain a real OAuth '
            'client ID (a real web client ID is ~70 chars and ends with '
            '.apps.googleusercontent.com). The placeholder prevents accidental '
            'commits of real credentials.',
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

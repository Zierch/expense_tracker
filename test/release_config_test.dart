// Security invariants for the release build and deployment.
//
// This app is published as a shared APK with personal financial records
// stored on-device. These tests lock in decisions that a future contributor
// could silently break, causing users to lose data or exposing backups.
//
// Read files from disk and assert that each invariant still holds.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

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
        final String gradle = _kotlinCode(
          File('android/app/build.gradle.kts').readAsStringSync(),
        );

        // The Flutter template ships `signingConfig = signingConfigs.getByName("debug")`
        // for release builds. Removing that line is what closes the hole: a debug-signed
        // APK is per-machine and recreatable, so a rebuild from anywhere else forces
        // every user to uninstall, deleting their financial database in the process.
        //
        // Forbidden as the quoted token rather than as one call shape, because Gradle
        // can reach a signing config through getByName("debug") or signingConfigs["debug"],
        // and checking only the first spelling leaves the second as a way back in. The
        // quoted string "debug" appears nowhere else in this file's code, so the token is
        // specific to signing configs; the `profile` build type that Flutter adds inherits
        // the debug config implicitly and never names it.
        expect(
          gradle,
          isNot(contains('"debug"')),
          reason:
              'SECURITY: nothing in build.gradle.kts may reference the debug signing '
              'config, in any spelling. If release used it, the shared APK would be '
              'signed with a per-machine keystore, so rebuilding anywhere else would '
              'force every user to uninstall, which deletes their financial database.',
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
            'SECURITY: do not add a <cross-platform-transfer> section. It would '
            'opt this app into transfers to iOS, and it cannot be configured '
            'correctly without an iOS counterpart to match bundleId and teamId. '
            'Its absence is what keeps the app out of that path.',
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


/// Returns [source] with Kotlin comments, and their contents, removed.
///
/// Assertions about this project's Gradle config have to test code rather than
/// prose: the header of build.gradle.kts deliberately names the template line it
/// refuses to copy, so a check run against the raw file text fails on the file's
/// own explanation.
///
/// This is not a Kotlin lexer. It understands line comments, block comments,
/// escaped quotes and triple-quoted strings, which is what build.gradle.kts
/// contains. A string template holding a quote inside a `"${...}"` expression
/// can still mislead the string tracking, so do not lean on it for anything
/// beyond the assertions in this file.
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

// The pure pieces of the in-app update flow — the parts that decide *whether*
// an update is offered at all — pinned without a network or a database.
//
// Two decisions here can quietly mislead every friend running the app: a
// version comparison that lists "1.10.0" below "1.2.1" (string comparison or
// padding error), and a checksum line parsed from release notes with a pattern
// that stops matching the format the notes use. Both live in
// `AppUpdateService`, where the network-facing code calls into them.

import 'dart:convert';

import 'package:expense_tracker/data/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A GitHub `/releases/latest` answer, built by `jsonEncode` so the escaping is
/// the library's job, not a string literal's.
String _releaseJson({
  String tag = 'v1.2.0',
  List<Map<String, Object?>> assets = const <Map<String, Object?>>[],
  String body = '',
}) {
  return jsonEncode(<String, Object?>{
    'tag_name': tag,
    'assets': assets,
    'body': body,
  });
}

const String _publishedChecksum =
    '3fbb304ab4301986873f01addd57d112ee140b5c81f53d7a44c0e1114cfaab48';

/// The release notes' build-details tail, warts and all, as `gh release
/// create --notes-file` produces it.
const String _releaseBody = '**Build details**\n'
    '\n'
    '- package `com.zierch.expense_tracker`, versionCode `4`, versionName `1.2.0`\n'
    '- minSdk 24 (Android 7.0), targetSdk 36\n'
    '- SHA-256 of this APK:\n'
    '  `$_publishedChecksum`\n'
    '- source: MIT, see `LICENSE`\n';

AppUpdateService _serviceReturning(http.Response Function(http.Request) reply) {
  return AppUpdateService(
    client: MockClient((http.Request request) async => reply(request)),
  );
}

void main() {
  group('isNewerThan compares versions numerically, part by part', () {
    const List<(String, String, bool)> cases = <(String, String, bool)>[
      ('1.1.1', '1.1.1', false), // equal is not newer
      ('1.1.1', '1.2.0', true), // minor goes up
      ('1.1.1', '1.1.2', true), // patch goes up
      ('1.2.0', '1.10.0', true), // real number order, not string order
      ('1.2', '1.2.0', false), // a missing part is zero
      ('1.2.9', '2.0.0', true), // major goes up
      ('9.0.0', '10.0.0', true), // two digits beat one
      ('1.1.1', '1.1.1.0', false), // padded equals unpadded
    ];

    for (final (String local, String remote, bool wanted) in cases) {
      test('$local vs $remote → $wanted', () {
        expect(AppUpdateService.isNewerThan(local, remote), wanted);
      });
    }

    test('a non-numeric version is an error, not a silent comparison', () {
      expect(
        () => AppUpdateService.isNewerThan('1.0.0', '1.2.0-beta'),
        throwsA(isA<UpdateException>()),
        reason: 'a shape this code cannot compare must fail loudly, or it '
            'would either nag forever or never offer an update',
      );
    });

    test('a leading v on either side is stripped before comparing', () {
      expect(AppUpdateService.isNewerThan('v1.1.1', '1.2.0'), isTrue);
      expect(AppUpdateService.isNewerThan('1.1.1', 'v1.2.0'), isTrue);
    });
  });

  group('fetchLatestRelease reads what the release pipeline publishes', () {
    test('happy path: tag, APK asset and published checksum', () async {
      final AppUpdateService service =
          _serviceReturning((http.Request _) => http.Response(
                _releaseJson(
                  tag: 'v1.3.1',
                  body: _releaseBody,
                  assets: <Map<String, Object?>>[
                    <String, Object?>{
                      'name': 'expense-tracker-1.3.1.apk',
                      'browser_download_url':
                          'https://github.com/Zierch/expense_tracker/releases/'
                              'download/v1.3.1/expense-tracker-1.3.1.apk',
                      'size': 1048576,
                    },
                  ],
                ),
                200,
              ));

      final RemoteRelease release = await service.fetchLatestRelease();

      expect(release.version, '1.3.1');
      expect(release.tagName, 'v1.3.1');
      expect(release.publishedSha256, _publishedChecksum);
      expect(release.sizeInBytes, 1048576);
      expect(release.downloadUrl.host, 'github.com');
      expect(release.downloadUrl.path, endsWith('expense-tracker-1.3.1.apk'));
    });

    test('the pre-1.3.1 asset name still updates those phones', () async {
      // v1.3.0 and older published `app-release.apk`. Dropping it would strand
      // exactly the phones that cannot read a name change from the future.
      final AppUpdateService service =
          _serviceReturning((http.Request _) => http.Response(
                _releaseJson(
                  tag: 'v1.2.0',
                  assets: <Map<String, Object?>>[
                    <String, Object?>{
                      'name': 'app-release.apk',
                      'browser_download_url':
                          'https://github.com/Zierch/expense_tracker/releases/'
                              'download/v1.2.0/app-release.apk',
                      'size': 10,
                    },
                  ],
                ),
                200,
              ));

      final RemoteRelease release = await service.fetchLatestRelease();

      expect(release.downloadUrl.path, endsWith('app-release.apk'));
    });

    test('a lone .apk under an unexpected name is still found', () async {
      final AppUpdateService service =
          _serviceReturning((http.Request _) => http.Response(
                _releaseJson(
                  tag: 'v2.0.0',
                  assets: <Map<String, Object?>>[
                    <String, Object?>{
                      'name': 'Expense-Tracker-2.0.0.apk',
                      'browser_download_url': 'https://github.com/x/y.apk',
                      'size': 10,
                    },
                  ],
                ),
                200,
              ));

      final RemoteRelease release = await service.fetchLatestRelease();

      expect(release.version, '2.0.0');
      expect(release.downloadUrl.path, endsWith('y.apk'));
    });

    test('two unexplained APKs are ambiguity, not an update', () async {
      final AppUpdateService service = _serviceReturning((http.Request _) =>
          http.Response(
            _releaseJson(
              tag: 'v2.0.0',
              assets: <Map<String, Object?>>[
                <String, Object?>{
                  'name': 'arm64.apk',
                  'browser_download_url': 'https://github.com/x/arm64.apk',
                  'size': 10,
                },
                <String, Object?>{
                  'name': 'armeabi.apk',
                  'browser_download_url': 'https://github.com/x/armeabi.apk',
                  'size': 10,
                },
              ],
            ),
            200,
          ));

      await expectLater(
        () => service.fetchLatestRelease(),
        throwsA(isA<UpdateException>()),
        reason: 'installing the wrong architecture is worse than not offering '
            'an update at all',
      );
    });

    test('the request identifies the app to GitHub', () async {
      http.Request? captured;
      final AppUpdateService service = _serviceReturning((http.Request r) {
        captured = r;
        return http.Response(
            _releaseJson(
                body: _releaseBody,
                assets: <Map<String, Object?>>[
                  <String, Object?>{
                    'name': 'app-release.apk',
                    'browser_download_url': 'https://github.com/x/app-release.apk',
                    'size': 1,
                  },
                ]),
            200);
      });

      await service.fetchLatestRelease();

      expect(captured!.url.host, 'api.github.com');
      expect(
        captured!.url.path,
        '/repos/Zierch/expense_tracker/releases/latest',
        reason: 'an update check for this app must ask about this repository',
      );
      expect(captured!.headers, contains('User-Agent'),
          reason: "GitHub's API rejects anonymous clients with no User-Agent");
    });

    test('a release without the APK is a loud error, not a silent no-op',
        () async {
      final AppUpdateService service =
          _serviceReturning((http.Request _) =>
              http.Response(_releaseJson(tag: 'v1.2.0'), 200));

      await expectLater(
        () => service.fetchLatestRelease(),
        throwsA(isA<UpdateException>()),
      );
    });

    test('GitHub rate limiting is reported in words for the user', () async {
      final AppUpdateService service = _serviceReturning(
          (http.Request _) => http.Response('{"message": "forbidden"}', 403));

      final String message = await _catchUpdateMessage(() async {
        await service.fetchLatestRelease();
      });
      expect(message, contains('rate'));
    });
  });

  group('the checksum pattern matches the release-notes format', () {
    // If the notes format ever drifts, downloads silently lose their
    // verification — worth pinning, because nothing else would notice.
    final RegExp pattern =
        RegExp(r'SHA-256 of this APK:.*?([a-f0-9]{64})', dotAll: true);

    test('the multi-line note form matches', () {
      expect(
        pattern.firstMatch(_releaseBody)?.group(1),
        _publishedChecksum,
      );
    });

    test('absence stays absence — no half a match', () {
      expect(pattern.firstMatch('no checksum anywhere'), isNull);
    });
  });
}

/// Runs [action] and returns its `UpdateException`'s message, or fails.
Future<String> _catchUpdateMessage(Future<void> Function() action) async {
  try {
    await action();
  } on UpdateException catch (error) {
    return error.message;
  }
  fail('the action was expected to fail with an UpdateException');
}

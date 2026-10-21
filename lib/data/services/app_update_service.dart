// Talking to GitHub about app updates.
//
// The app ships as an APK on the GitHub Releases page, far from the Play Store
// and its automatic updates. A "check for update" therefore asks GitHub's API
// for the latest release of this repository, compares its tag to the version
// the phone is running, and — if it is newer — hands back the download address
// of the release APK together with the SHA-256 the release notes publish.
//
// Two properties worth keeping:
//
// * Only `/releases/latest` is used and nothing user-specific is attached: no
//   account, no token, no device identifier. GitHub sees an IP address and a
//   User-Agent string, nothing else.
// * TLS protects the bytes in transit; the checksum the release notes publish
//   protects them against the repository changing between "released" and
//   "downloaded". A download that does not match is deleted, never installed.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// A published release worth offering to install.
class RemoteRelease {
  const RemoteRelease({
    required this.version,
    required this.tagName,
    required this.downloadUrl,
    required this.sizeInBytes,
    required this.publishedSha256,
  });

  /// The numeric version — `tag_name` without its leading `v`.
  final String version;

  /// The raw tag as GitHub published it, e.g. `v1.2.0`.
  final String tagName;

  /// Download address of the release APK.
  final Uri downloadUrl;

  /// What GitHub says the APK weighs, so a summary can say roughly how much of
  /// the download has arrived even if the response hides its length.
  final int sizeInBytes;

  /// The SHA-256 the release notes publish, or `null` when the notes carry
  /// none. A download is only checked against this when it is present, and only
  /// kept when the check passes.
  final String? publishedSha256;
}

/// Something went wrong with checking or downloading, in words for the user.
class UpdateException implements Exception {
  UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the newest release and puts its APK on disk, verified.
///
/// [repository] is `owner/name` on GitHub; passing another value is for tests.
class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    String repository = 'Zierch/expense_tracker',
  })  : _client = client ?? http.Client(),
        _releasesUrl =
            Uri.parse('https://api.github.com/repos/$repository/releases/latest');

  final http.Client _client;
  final Uri _releasesUrl;

  /// The asset name releases up to and including v1.3.0 published: a name that
  /// said nothing about which app — or which version — the file belongs to.
  /// Still looked for, so phones on those versions can update themselves.
  static const String _legacyApkFileName = 'app-release.apk';

  /// The checksum line in every release note, in exactly the form the notes
  /// use: the label, any whitespace (including the line break), an optional
  /// backtick, the 64 hex digits, and the backtick. Pinned by
  /// `test/app_update_test.dart`; a looser `.*?` here could swallow the
  /// distance to an unrelated hex string, so this stays anchored tight.
  static final RegExp _checksumPattern = RegExp(
    r'SHA-256 of this APK:\s*`?([a-f0-9]{64})`?',
  );

  /// The APK's name, like `expense-tracker-<version>.apk`: the asset name every
  /// release from v1.3.1 on publishes, and the name the download lands under,
  /// so a downloaded file says which app and which version it is, and
  /// re-downloading a later version cannot "overwrite" an old one by accident.
  String apkFileNameFor(String version) => 'expense-tracker-$version.apk';

  /// Asks GitHub for the newest published release.
  Future<RemoteRelease> fetchLatestRelease() async {
    final http.Response response =
        await _client.get(_releasesUrl, headers: <String, String>{
      'Accept': 'application/vnd.github+json',
      // GitHub's API needs an identifying User-Agent on every call.
      'User-Agent': 'expense-tracker (github.com/Zierch/expense_tracker)',
    });

    if (response.statusCode == 403) {
      throw UpdateException(
        'GitHub has rate-limited the update check — try again a little later.',
      );
    }
    if (response.statusCode != 200) {
      throw UpdateException(
        'GitHub answered ${response.statusCode} when asked about the latest '
        'release.',
      );
    }

    final Object? decoded;
    try {
      decoded = json.decode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw UpdateException('The release information came back unreadable.');
    }
    if (decoded is! Map<String, Object?>) {
      throw UpdateException('The release information came back unreadable.');
    }

    final Object? tagName = decoded['tag_name'];
    if (tagName is! String || tagName.isEmpty) {
      throw UpdateException('The newest release does not state a version.');
    }

    final Object? assets = decoded['assets'];
    final String version = _stripTagPrefix(tagName);
    final Object? apkAsset = assets is List<Object?>
        ? _findApkAsset(assets, version)
        : null;
    if (apkAsset is! Map<String, Object?>) {
      throw UpdateException('The newest release does not carry the APK.');
    }

    final Object? rawDownloadUrl = apkAsset['browser_download_url'];
    if (rawDownloadUrl is! String) {
      throw UpdateException(
          'The newest release does not state where to download the APK from.');
    }

    final Object? rawSize = apkAsset['size'];
    if (rawSize is! int) {
      throw UpdateException('The newest release does not state a file size.');
    }

    final Object? body = decoded['body'];

    return RemoteRelease(
      version: version,
      tagName: tagName,
      downloadUrl: Uri.parse(rawDownloadUrl),
      sizeInBytes: rawSize,
      publishedSha256:
          _checksumPattern.firstMatch(body is String ? body : '')?.group(1),
    );
  }

  /// The release's APK asset, or `null` when it carries none to pick.
  ///
  /// The name a release uses moved from `app-release.apk` to
  /// `expense-tracker-<version>.apk` in v1.3.1, so both are accepted; a lone
  /// `.apk` under some other name is taken too, because a release pipeline that
  /// renames the file should not silently leave every phone unable to update —
  /// but only when its name states the release's version, since a lone stale
  /// APK under an unversioned name would otherwise be offered as the newest
  /// release. Two unexplained APKs are ambiguity, not an update, and are
  /// refused.
  Object? _findApkAsset(List<Object?> assets, String version) {
    final String wanted = apkFileNameFor(version);
    // `1.4.0` must not count as naming the version of `11.4.0`.
    final RegExp namesVersion = RegExp(
      '(?<![0-9])${RegExp.escape(version)}(?![0-9])',
    );
    Object? loneApk;
    int apkCount = 0;
    for (final Object? asset in assets) {
      if (asset is! Map<String, Object?>) continue;
      final Object? name = asset['name'];
      if (name is! String || !name.toLowerCase().endsWith('.apk')) continue;
      final String lowerCaseName = name.toLowerCase();
      if (lowerCaseName == wanted || lowerCaseName == _legacyApkFileName) {
        return asset;
      }
      if (namesVersion.hasMatch(lowerCaseName)) {
        loneApk = asset;
        apkCount++;
      }
    }
    return apkCount == 1 ? loneApk : null;
  }

  /// Downloads [release] and verifies it against the checksum the release
  /// published, if there is one.
  ///
  /// Returns the absolute file path, ready to hand to the platform installer.
  /// A download that fails partway, or fails the checksum, is deleted: the
  /// installer never gets half a file.
  Future<String> downloadApk(
    RemoteRelease release, {
    void Function(double fraction)? onProgress,
  }) async {
    final Directory cache = await getTemporaryDirectory();
    final Directory apkDir = Directory(path.join(cache.path, 'apk'))
      ..create(recursive: true);
    final File file =
        File(path.join(apkDir.path, apkFileNameFor(release.version)));

    final http.StreamedResponse response =
        await _client.send(http.Request('GET', release.downloadUrl));

    if (response.statusCode != 200) {
      throw UpdateException(
        'The download did not start — GitHub answered '
        '${response.statusCode} instead of delivering the APK.',
      );
    }

    final int total = response.contentLength ?? release.sizeInBytes;
    final IOSink sink = file.openWrite();
    int received = 0;
    try {
      await for (final List<int> chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          onProgress?.call(math.min(received / total, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
    } on Object {
      // A partial APK is not something the installer may ever be shown: drop
      // whatever landed and let the error surface.
      try {
        await sink.close();
      } on Object {
        // The important thing is to not hide the download failure that
        // brought us here.
      }
      try {
        await file.delete();
      } on FileSystemException {
        // A file that refused to be deleted will simply be overwritten by the
        // next attempt, when the app retries the download.
      }
      rethrow;
    }

    if (release.publishedSha256 != null) {
      final Digest digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != release.publishedSha256) {
        try {
          await file.delete();
        } on FileSystemException {
          // The error message below is the part the user needs to see.
        }
        throw UpdateException(
          'The downloaded APK does not match the checksum the release '
          'published — it was deleted instead of offered for install.',
        );
      }
    }

    return file.path;
  }

  /// Whether [remoteVersion] is strictly newer than [localVersion].
  ///
  /// Both are `x.y.z` (an optional leading `v` is stripped), compared part by
  /// part numerically, with a missing part counting as zero — so `1.2.0 <
  /// 1.2.1 < 1.3.0 < 1.10.0`, and an equal version is correctly not "newer".
  static bool isNewerThan(String localVersion, String remoteVersion) {
    final List<int> local = _versionParts(localVersion);
    final List<int> remote = _versionParts(remoteVersion);
    final int length =
        local.length > remote.length ? local.length : remote.length;
    for (int i = 0; i < length; i++) {
      final int left = i < local.length ? local[i] : 0;
      final int right = i < remote.length ? remote[i] : 0;
      if (right != left) return right > left;
    }
    return false;
  }

  /// Splits a version into numeric parts; anything not `x.y.z`-shaped fails
  /// loudly, because silently comparing a wrong shape would mean either never
  /// seeing an update or nagging about one forever.
  static List<int> _versionParts(String version) {
    final String clean = version.startsWith('v') ? version.substring(1) : version;
    final List<int> parts = <int>[];
    for (final String piece in clean.split('.')) {
      final int? number = int.tryParse(piece);
      if (number == null) {
        throw UpdateException(
          'The version "$version" is not in the expected form, so it could not '
          'be compared.',
        );
      }
      parts.add(number);
    }
    return parts;
  }

  static String _stripTagPrefix(String tagName) =>
      tagName.startsWith('v') ? tagName.substring(1) : tagName;
}

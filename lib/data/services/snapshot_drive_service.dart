import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:expense_tracker/data/services/google_config.dart';
import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:http/http.dart' as http;

/// Handles safe Drive snapshot listing, upload, verification, and retention.
///
/// Invariants:
/// - Generates unique filenames: `expense-tracker-snapshot-yyyyMMddTHHmmss-<nonce>.json`.
/// - Verifies every upload by reading back content bytes and matching before pruning.
/// - Retention policy: keeps the latest 3 owned snapshots; NEVER deletes legacy monthly backups.
/// - Fails closed: if listing is ambiguous, verification fails, or concurrency is uncertain,
///   pruning is aborted and no files are removed.
class SnapshotDriveService {
  SnapshotDriveService({
    required http.Client client,
    required Future<Map<String, String>> Function() headers,
    DateTime Function()? clock,
    Random? random,
  })  : _client = client,
        _headers = headers,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final http.Client _client;
  final Future<Map<String, String>> Function() _headers;
  final DateTime Function() _clock;
  final Random _random;

  static const String _drive = 'https://www.googleapis.com/drive/v3';
  static const String _upload = 'https://www.googleapis.com/upload/drive/v3';
  static const String _folderMime = 'application/vnd.google-apps.folder';
  static const String _jsonMime = 'application/json';

  static final RegExp _ownedSnapshotName = RegExp(
    r'^expense-tracker-snapshot-\d{8}T\d{6}-[a-f0-9]{16}\.json$',
  );

  static final RegExp _legacyMonthlyName = RegExp(
    r'^expense-tracker-\d{4}-\d{2}\.json$',
  );

  static bool _operationLocked = false;

  /// Returns whether a filename is an owned snapshot.
  static bool isOwnedSnapshot(String name) => _ownedSnapshotName.hasMatch(name);

  /// Returns whether a filename is a legacy monthly backup.
  static bool isLegacyMonthlyBackup(String name) =>
      _legacyMonthlyName.hasMatch(name);

  /// Uploads [bytes] as a new snapshot, verifies download bytes match, and retains latest 3 owned snapshots.
  Future<String> uploadSnapshot(List<int> bytes, {String? folderName}) async {
    if (_operationLocked) {
      throw BackupException(
        'A snapshot backup operation is already running. Try again later.',
      );
    }
    _operationLocked = true;
    try {
      final Map<String, String> auth = await _headers();
      final String folder =
          await _getFolder(auth, folderName ?? GoogleConfig.driveFolderName);

      final DateTime now = _clock().toUtc();
      final String stamp =
          now.toIso8601String().replaceAll(RegExp(r'[-:]'), '').substring(0, 15);
      final String nonce = List<String>.generate(
        8,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final String name = 'expense-tracker-snapshot-$stamp-$nonce.json';

      final String fileId = await _uploadBytes(auth, folder, name, bytes);

      // Verify listing includes the file and metadata is consistent
      final List<Map<String, dynamic>> rows = await _listFolder(auth, folder);
      final Map<String, dynamic> uploaded = rows.singleWhere(
        (Map<String, dynamic> f) => f['id'] == fileId,
        orElse: () => <String, dynamic>{},
      );

      if (uploaded.isEmpty ||
          uploaded['name'] != name ||
          uploaded['mimeType'] != _jsonMime ||
          !(uploaded['parents'] as List<dynamic>? ?? <dynamic>[]).contains(folder) ||
          uploaded['ownedByMe'] != true) {
        throw BackupException(
          'Snapshot upload could not be verified in Drive listing; aborting retention pruning.',
        );
      }

      // Download bytes and verify content
      final List<int> downloaded = await _download(auth, fileId);
      if (!_sameBytes(bytes, downloaded)) {
        throw BackupException(
          'Snapshot upload byte verification failed; aborting retention pruning.',
        );
      }

      // Find candidates for pruning: only owned snapshot files, never legacy files
      final List<Map<String, dynamic>> snapshotCandidates = rows.where((Map<String, dynamic> f) {
        final String fName = f['name'] as String? ?? '';
        final bool owned = f['ownedByMe'] == true;
        final bool jsonType = f['mimeType'] == _jsonMime;
        final bool inParent = (f['parents'] as List<dynamic>? ?? <dynamic>[]).contains(folder);
        return owned && jsonType && inParent && _ownedSnapshotName.hasMatch(fName);
      }).toList();

      // Ensure uploaded snapshot is in the candidate list exactly once
      if (snapshotCandidates.where((Map<String, dynamic> f) => f['id'] == fileId).length != 1) {
        throw BackupException(
          'Drive snapshot listing is ambiguous; aborting retention pruning.',
        );
      }

      // Sort newest to oldest by filename (contains ISO date-time stamp)
      snapshotCandidates.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final String nameA = a['name'] as String? ?? '';
        final String nameB = b['name'] as String? ?? '';
        return nameB.compareTo(nameA);
      });

      // Keep latest 3 owned snapshots, prune older ones (index 3+)
      for (final Map<String, dynamic> old in snapshotCandidates.skip(3)) {
        final String oldName = old['name'] as String? ?? '';
        if (_legacyMonthlyName.hasMatch(oldName)) {
          // Extra defensive check: NEVER delete a legacy monthly file
          continue;
        }

        final String? oldId = old['id'] as String?;
        if (oldId == null || oldId.isEmpty) continue;

        final http.Response response = await _client.delete(
          Uri.parse('$_drive/files/${Uri.encodeComponent(oldId)}'),
          headers: auth,
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw BackupException(
            'Snapshot retention pruning failed for file $oldId (HTTP ${response.statusCode}).',
          );
        }
      }

      return name;
    } finally {
      _operationLocked = false;
    }
  }

  /// Lists all owned snapshots in the target folder, sorted newest first.
  Future<List<Map<String, dynamic>>> listOwnedSnapshots({String? folderName}) async {
    final Map<String, String> auth = await _headers();
    final String folder =
        await _getFolder(auth, folderName ?? GoogleConfig.driveFolderName);
    final List<Map<String, dynamic>> rows = await _listFolder(auth, folder);

    final List<Map<String, dynamic>> snapshots = rows.where((Map<String, dynamic> f) {
      final String name = f['name'] as String? ?? '';
      return f['ownedByMe'] == true &&
          f['mimeType'] == _jsonMime &&
          _ownedSnapshotName.hasMatch(name);
    }).toList();

    snapshots.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final String nameA = a['name'] as String? ?? '';
      final String nameB = b['name'] as String? ?? '';
      return nameB.compareTo(nameA);
    });

    return snapshots;
  }

  /// Lists legacy monthly backup files in the target folder.
  Future<List<Map<String, dynamic>>> listLegacyMonthlyBackups({String? folderName}) async {
    final Map<String, String> auth = await _headers();
    final String folder =
        await _getFolder(auth, folderName ?? GoogleConfig.driveFolderName);
    final List<Map<String, dynamic>> rows = await _listFolder(auth, folder);

    final List<Map<String, dynamic>> legacy = rows.where((Map<String, dynamic> f) {
      final String name = f['name'] as String? ?? '';
      return f['mimeType'] == _jsonMime && _legacyMonthlyName.hasMatch(name);
    }).toList();

    legacy.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final String nameA = a['name'] as String? ?? '';
      final String nameB = b['name'] as String? ?? '';
      return nameB.compareTo(nameA);
    });

    return legacy;
  }

  /// Downloads content bytes for a file by [fileId].
  Future<List<int>> downloadFile(String fileId) async {
    final Map<String, String> auth = await _headers();
    return _download(auth, fileId);
  }

  Future<String> _getFolder(Map<String, String> auth, String name) async {
    final List<Map<String, dynamic>> rows = await _query(
      auth,
      "name = '${_escape(name)}' and mimeType = '$_folderMime' and trashed = false",
      'files(id,name)',
    );
    if (rows.length != 1 || rows.single['id'] is! String) {
      throw BackupException(
        'Drive backup folder is missing or ambiguous ($name).',
      );
    }
    return rows.single['id'] as String;
  }

  Future<List<Map<String, dynamic>>> _listFolder(
    Map<String, String> auth,
    String folder,
  ) {
    return _query(
      auth,
      "'${_escape(folder)}' in parents and trashed = false",
      'files(id,name,mimeType,parents,ownedByMe),nextPageToken',
    );
  }

  Future<List<Map<String, dynamic>>> _query(
    Map<String, String> auth,
    String q,
    String fields,
  ) async {
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
    String? token;

    for (int i = 0; i < 10; i++) {
      final Uri uri = Uri.parse('$_drive/files').replace(
        queryParameters: <String, String>{
          'q': q,
          'spaces': 'drive',
          'pageSize': '100',
          'fields': fields,
          if (token != null) 'pageToken': token,
        },
      );

      final http.Response r = await _client.get(uri, headers: auth);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw BackupException(
          'Could not list Google Drive files (HTTP ${r.statusCode}).',
        );
      }

      final Map<String, dynamic> body =
          jsonDecode(r.body) as Map<String, dynamic>;
      if (body['files'] is! List) {
        throw BackupException('Drive returned an ambiguous file listing.');
      }

      result.addAll((body['files'] as List<dynamic>).cast<Map<String, dynamic>>());
      token = body['nextPageToken'] as String?;
      if (token == null) return result;
    }

    throw BackupException(
      'Drive listing exceeded pagination limits; aborting operation.',
    );
  }

  Future<String> _uploadBytes(
    Map<String, String> auth,
    String folder,
    String name,
    List<int> bytes,
  ) async {
    final String boundary =
        'snapshot-${name.hashCode.abs().toRadixString(16)}';
    final List<int> body = <int>[
      ...utf8.encode(
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n',
      ),
      ...utf8.encode(
        jsonEncode(<String, dynamic>{
          'name': name,
          'mimeType': _jsonMime,
          'parents': <String>[folder],
        }),
      ),
      ...utf8.encode(
        '\r\n--$boundary\r\nContent-Type: application/json\r\n\r\n',
      ),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--'),
    ];

    final http.Response r = await _client.post(
      Uri.parse('$_upload/files?uploadType=multipart&fields=id'),
      headers: <String, String>{
        ...auth,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );

    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw BackupException(
        'Snapshot upload failed (HTTP ${r.statusCode}).',
      );
    }

    final Object? id = (jsonDecode(r.body) as Map<String, dynamic>)['id'];
    if (id is! String || id.isEmpty) {
      throw BackupException('Snapshot upload response was ambiguous.');
    }
    return id;
  }

  Future<List<int>> _download(Map<String, String> auth, String id) async {
    final http.Response r = await _client.get(
      Uri.parse('$_drive/files/${Uri.encodeComponent(id)}?alt=media'),
      headers: auth,
    );
    if (r.statusCode != 200) {
      throw BackupException(
        'Could not verify uploaded snapshot (HTTP ${r.statusCode}).',
      );
    }
    return r.bodyBytes;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _escape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
}

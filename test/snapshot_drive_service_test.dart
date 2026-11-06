import 'dart:convert';
import 'dart:math';

import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:expense_tracker/data/services/snapshot_drive_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final http.Response res = await handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
      contentLength: res.bodyBytes.length,
    );
  }
}

class _FixedRandom implements Random {
  _FixedRandom(this.bytes);

  final List<int> bytes;
  int _index = 0;

  @override
  int nextInt(int max) {
    final int val = bytes[_index % bytes.length];
    _index++;
    return val;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.0;
}

http.Response _jsonResponse(dynamic data, {int status = 200}) {
  return http.Response(
    jsonEncode(data),
    status,
    headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  group('SnapshotDriveService', () {
    test('isOwnedSnapshot and isLegacyMonthlyBackup patterns', () {
      expect(
        SnapshotDriveService.isOwnedSnapshot(
          'expense-tracker-snapshot-20261106T120000-0123456789abcdef.json',
        ),
        isTrue,
      );
      expect(
        SnapshotDriveService.isOwnedSnapshot('expense-tracker-2026-10.json'),
        isFalse,
      );
      expect(
        SnapshotDriveService.isLegacyMonthlyBackup('expense-tracker-2026-10.json'),
        isTrue,
      );
      expect(
        SnapshotDriveService.isLegacyMonthlyBackup(
          'expense-tracker-snapshot-20261106T120000-0123456789abcdef.json',
        ),
        isFalse,
      );
    });

    test('uploadSnapshot verifies bytes and prunes beyond 3 owned snapshots', () async {
      final List<int> payload = utf8.encode('{"test":"payload"}');
      final List<String> deletedIds = <String>[];

      final _FakeClient client = _FakeClient((http.BaseRequest req) async {
        final Uri url = req.url;
        if (req.method == 'GET' && url.path == '/drive/v3/files') {
          final String q = url.queryParameters['q'] ?? '';
          if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
            return _jsonResponse(<String, dynamic>{
              'files': <dynamic>[
                <String, dynamic>{'id': 'folder-1', 'name': 'Expense Tracker'},
              ],
            });
          }
          if (q.contains("'folder-1' in parents")) {
            return _jsonResponse(<String, dynamic>{
              'files': <dynamic>[
                <String, dynamic>{
                  'id': 'new-file-id',
                  'name': 'expense-tracker-snapshot-20261106T120000-0102030405060708.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
                <String, dynamic>{
                  'id': 'snap-2',
                  'name': 'expense-tracker-snapshot-20261105T120000-0000000000000002.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
                <String, dynamic>{
                  'id': 'snap-3',
                  'name': 'expense-tracker-snapshot-20261104T120000-0000000000000003.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
                <String, dynamic>{
                  'id': 'snap-4',
                  'name': 'expense-tracker-snapshot-20261103T120000-0000000000000004.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
                // Legacy monthly file - MUST NOT be deleted
                <String, dynamic>{
                  'id': 'legacy-1',
                  'name': 'expense-tracker-2026-10.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
              ],
            });
          }
        } else if (req.method == 'POST' && url.path == '/upload/drive/v3/files') {
          return _jsonResponse(<String, dynamic>{'id': 'new-file-id'});
        } else if (req.method == 'GET' && url.path == '/drive/v3/files/new-file-id') {
          return http.Response.bytes(payload, 200);
        } else if (req.method == 'DELETE' && url.path == '/drive/v3/files/snap-4') {
          deletedIds.add('snap-4');
          return http.Response('', 204);
        }
        return http.Response('Not found', 404);
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
        clock: () => DateTime.utc(2026, 11, 6, 12, 0, 0),
        random: _FixedRandom(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );

      final String uploadedName = await service.uploadSnapshot(payload);

      expect(uploadedName, 'expense-tracker-snapshot-20261106T120000-0102030405060708.json');
      expect(deletedIds, <String>['snap-4']);
      expect(deletedIds, isNot(contains('legacy-1')));
    });

    test('uploadSnapshot fails closed on byte mismatch without pruning', () async {
      final List<int> payload = utf8.encode('{"test":"payload"}');
      final List<int> corrupted = utf8.encode('{"test":"corrupted"}');

      final _FakeClient client = _FakeClient((http.BaseRequest req) async {
        final Uri url = req.url;
        if (req.method == 'GET' && url.path == '/drive/v3/files') {
          final String q = url.queryParameters['q'] ?? '';
          if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
            return _jsonResponse(<String, dynamic>{
              'files': <dynamic>[
                <String, dynamic>{'id': 'folder-1', 'name': 'Expense Tracker'},
              ],
            });
          }
          return _jsonResponse(<String, dynamic>{
            'files': <dynamic>[
              <String, dynamic>{
                'id': 'new-file-id',
                'name': 'expense-tracker-snapshot-20261106T120000-0102030405060708.json',
                'mimeType': 'application/json',
                'parents': <dynamic>['folder-1'],
                'ownedByMe': true,
              },
              <String, dynamic>{
                'id': 'snap-old',
                'name': 'expense-tracker-snapshot-20261001T000000-0000000000000001.json',
                'mimeType': 'application/json',
                'parents': <dynamic>['folder-1'],
                'ownedByMe': true,
              },
            ],
          });
        } else if (req.method == 'POST' && url.path == '/upload/drive/v3/files') {
          return _jsonResponse(<String, dynamic>{'id': 'new-file-id'});
        } else if (req.method == 'GET' && url.path == '/drive/v3/files/new-file-id') {
          return http.Response.bytes(corrupted, 200);
        } else if (req.method == 'DELETE') {
          fail('DELETE must not be called when verification fails');
        }
        return http.Response('Not found', 404);
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
        clock: () => DateTime.utc(2026, 11, 6, 12, 0, 0),
        random: _FixedRandom(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );

      expect(
        () => service.uploadSnapshot(payload),
        throwsA(
          isA<BackupException>().having(
            (BackupException e) => e.message,
            'message',
            contains('Snapshot upload byte verification failed'),
          ),
        ),
      );
    });

    test('uploadSnapshot fails closed on ambiguous timestamps without pruning', () async {
      final List<int> payload = utf8.encode('{"test":"payload"}');

      final _FakeClient client = _FakeClient((http.BaseRequest req) async {
        final Uri url = req.url;
        if (req.method == 'GET' && url.path == '/drive/v3/files') {
          final String q = url.queryParameters['q'] ?? '';
          if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
            return _jsonResponse(<String, dynamic>{
              'files': <dynamic>[
                <String, dynamic>{'id': 'folder-1', 'name': 'Expense Tracker'},
              ],
            });
          }
          if (q.contains("'folder-1' in parents")) {
            return _jsonResponse(<String, dynamic>{
              'files': <dynamic>[
                <String, dynamic>{
                  'id': 'new-file-id',
                  'name': 'expense-tracker-snapshot-20261106T120000-0102030405060708.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
                // Two snapshots with identical timestamp 20261105T120000
                <String, dynamic>{
                  'id': 'snap-2a',
                  'name': 'expense-tracker-snapshot-20261105T120000-aaaaaaaaaaaaaaaa.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
                <String, dynamic>{
                  'id': 'snap-2b',
                  'name': 'expense-tracker-snapshot-20261105T120000-bbbbbbbbbbbbbbbb.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
                <String, dynamic>{
                  'id': 'snap-4',
                  'name': 'expense-tracker-snapshot-20261103T120000-0000000000000004.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
              ],
            });
          }
        } else if (req.method == 'POST' && url.path == '/upload/drive/v3/files') {
          return _jsonResponse(<String, dynamic>{'id': 'new-file-id'});
        } else if (req.method == 'GET' && url.path == '/drive/v3/files/new-file-id') {
          return http.Response.bytes(payload, 200);
        } else if (req.method == 'DELETE') {
          fail('DELETE must not be called when timestamps are ambiguous');
        }
        return http.Response('Not found', 404);
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
        clock: () => DateTime.utc(2026, 11, 6, 12, 0, 0),
        random: _FixedRandom(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );

      expect(
        () => service.uploadSnapshot(payload),
        throwsA(
          isA<BackupException>().having(
            (BackupException e) => e.message,
            'message',
            contains('timestamps are ambiguous'),
          ),
        ),
      );
    });

    test('uploadSnapshot fails closed on concurrent writer without pruning', () async {
      final List<int> payload = utf8.encode('{"test":"payload"}');

      final _FakeClient client = _FakeClient((http.BaseRequest req) async {
        final Uri url = req.url;
        if (req.method == 'GET' && url.path == '/drive/v3/files') {
          final String q = url.queryParameters['q'] ?? '';
          if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
            return _jsonResponse(<String, dynamic>{
              'files': <dynamic>[
                <String, dynamic>{'id': 'folder-1', 'name': 'Expense Tracker'},
              ],
            });
          }
          if (q.contains("'folder-1' in parents")) {
            return _jsonResponse(<String, dynamic>{
              'files': <dynamic>[
                // Snapshot from concurrent writer with newer timestamp
                <String, dynamic>{
                  'id': 'concurrent-newer-id',
                  'name': 'expense-tracker-snapshot-20261106T120500-cccccccccccccccc.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
                <String, dynamic>{
                  'id': 'new-file-id',
                  'name': 'expense-tracker-snapshot-20261106T120000-0102030405060708.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
                <String, dynamic>{
                  'id': 'snap-3',
                  'name': 'expense-tracker-snapshot-20261104T120000-0000000000000003.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
                <String, dynamic>{
                  'id': 'snap-4',
                  'name': 'expense-tracker-snapshot-20261103T120000-0000000000000004.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                },
              ],
            });
          }
        } else if (req.method == 'POST' && url.path == '/upload/drive/v3/files') {
          return _jsonResponse(<String, dynamic>{'id': 'new-file-id'});
        } else if (req.method == 'GET' && url.path == '/drive/v3/files/new-file-id') {
          return http.Response.bytes(payload, 200);
        } else if (req.method == 'DELETE') {
          fail('DELETE must not be called when concurrent writer is detected');
        }
        return http.Response('Not found', 404);
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
        clock: () => DateTime.utc(2026, 11, 6, 12, 0, 0),
        random: _FixedRandom(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );

      expect(
        () => service.uploadSnapshot(payload),
        throwsA(
          isA<BackupException>().having(
            (BackupException e) => e.message,
            'message',
            contains('concurrent writer'),
          ),
        ),
      );
    });

    test('uploadSnapshot creates folder via safe method on first upload when missing', () async {
      final List<int> payload = utf8.encode('{"test":"payload"}');
      bool folderCreated = false;

      final _FakeClient client = _FakeClient((http.BaseRequest req) async {
        final Uri url = req.url;
        if (req.method == 'GET' && url.path == '/drive/v3/files') {
          final String q = url.queryParameters['q'] ?? '';
          if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
            // First search: folder is missing initially
            if (!folderCreated) {
              return _jsonResponse(<String, dynamic>{'files': <dynamic>[]});
            }
            return _jsonResponse(<String, dynamic>{
              'files': <dynamic>[
                <String, dynamic>{'id': 'created-folder-id', 'name': 'Expense Tracker'},
              ],
            });
          }
          if (q.contains("'created-folder-id' in parents")) {
            return _jsonResponse(<String, dynamic>{
              'files': <dynamic>[
                <String, dynamic>{
                  'id': 'new-file-id',
                  'name': 'expense-tracker-snapshot-20261106T120000-0102030405060708.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['created-folder-id'],
                  'ownedByMe': true,
                },
              ],
            });
          }
        } else if (req.method == 'POST' && url.path == '/drive/v3/files') {
          // Folder creation
          folderCreated = true;
          return _jsonResponse(<String, dynamic>{'id': 'created-folder-id'});
        } else if (req.method == 'POST' && url.path == '/upload/drive/v3/files') {
          return _jsonResponse(<String, dynamic>{'id': 'new-file-id'});
        } else if (req.method == 'GET' && url.path == '/drive/v3/files/new-file-id') {
          return http.Response.bytes(payload, 200);
        }
        return http.Response('Not found', 404);
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
        clock: () => DateTime.utc(2026, 11, 6, 12, 0, 0),
        random: _FixedRandom(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );

      final String uploadedName = await service.uploadSnapshot(payload);
      expect(uploadedName, 'expense-tracker-snapshot-20261106T120000-0102030405060708.json');
      expect(folderCreated, isTrue);
    });

    test('uploadSnapshot fails closed on ambiguous folder without uploading', () async {
      final _FakeClient client = _FakeClient((http.BaseRequest req) async {
        return _jsonResponse(<String, dynamic>{
          'files': <dynamic>[
            <String, dynamic>{'id': 'f1', 'name': 'Expense Tracker'},
            <String, dynamic>{'id': 'f2', 'name': 'Expense Tracker'},
          ],
        });
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
      );

      expect(
        () => service.uploadSnapshot(<int>[1, 2, 3]),
        throwsA(
          isA<BackupException>().having(
            (BackupException e) => e.message,
            'message',
            contains('missing or ambiguous'),
          ),
        ),
      );
    });

    test('listOwnedSnapshots and listLegacyMonthlyBackups', () async {
      final _FakeClient client = _FakeClient((http.BaseRequest req) async {
        final Uri url = req.url;
        final String q = url.queryParameters['q'] ?? '';
        if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
          return _jsonResponse(<String, dynamic>{
            'files': <dynamic>[
              <String, dynamic>{'id': 'folder-1', 'name': 'Expense Tracker'},
            ],
          });
        }
        return _jsonResponse(<String, dynamic>{
          'files': <dynamic>[
            <String, dynamic>{
              'id': 's1',
              'name': 'expense-tracker-snapshot-20261106T120000-0000000000000001.json',
              'mimeType': 'application/json',
              'parents': <dynamic>['folder-1'],
              'ownedByMe': true,
            },
            <String, dynamic>{
              'id': 'm1',
              'name': 'expense-tracker-2026-10.json',
              'mimeType': 'application/json',
              'parents': <dynamic>['folder-1'],
              'ownedByMe': true,
            },
          ],
        });
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
      );

      final List<Map<String, dynamic>> snapshots = await service.listOwnedSnapshots();
      expect(snapshots, hasLength(1));
      expect(snapshots.first['id'], 's1');

      final List<Map<String, dynamic>> legacy = await service.listLegacyMonthlyBackups();
      expect(legacy, hasLength(1));
      expect(legacy.first['id'], 'm1');
    });

    test('listOwnedSnapshots and listLegacyMonthlyBackups return empty when folder is missing', () async {
      final _FakeClient client = _FakeClient((http.BaseRequest req) async {
        return _jsonResponse(<String, dynamic>{'files': <dynamic>[]});
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
      );

      final List<Map<String, dynamic>> snapshots = await service.listOwnedSnapshots();
      expect(snapshots, isEmpty);

      final List<Map<String, dynamic>> legacy = await service.listLegacyMonthlyBackups();
      expect(legacy, isEmpty);
    });

    test('downloadFile returns raw bytes', () async {
      final List<int> expected = utf8.encode('{"hello":"world"}');
      final _FakeClient client = _FakeClient((http.BaseRequest req) async {
        if (req.url.path == '/drive/v3/files/file-123') {
          return http.Response.bytes(expected, 200);
        }
        return http.Response('Not found', 404);
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
      );

      final List<int> bytes = await service.downloadFile('file-123');
      expect(bytes, equals(expected));
    });
  });
}

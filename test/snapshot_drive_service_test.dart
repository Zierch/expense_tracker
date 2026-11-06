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
                  'createdTime': '2026-11-06T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-2',
                  'name': 'expense-tracker-snapshot-20261105T120000-0000000000000002.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-05T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-3',
                  'name': 'expense-tracker-snapshot-20261104T120000-0000000000000003.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-04T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-4',
                  'name': 'expense-tracker-snapshot-20261103T120000-0000000000000004.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-03T12:00:00.000Z',
                },
                // Legacy monthly file - MUST NOT be deleted
                <String, dynamic>{
                  'id': 'legacy-1',
                  'name': 'expense-tracker-2026-10.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-10-31T12:00:00.000Z',
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

      final http.BaseRequest listingReq = client.requests.firstWhere(
        (http.BaseRequest r) =>
            r.url.path == '/drive/v3/files' &&
            (r.url.queryParameters['q'] ?? '').contains("'folder-1' in parents"),
      );
      expect(listingReq.url.queryParameters['fields'], contains('createdTime'));
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
                'createdTime': '2026-11-06T12:00:00.000Z',
              },
              <String, dynamic>{
                'id': 'snap-old',
                'name': 'expense-tracker-snapshot-20261001T000000-0000000000000001.json',
                'mimeType': 'application/json',
                'parents': <dynamic>['folder-1'],
                'ownedByMe': true,
                'createdTime': '2026-10-01T00:00:00.000Z',
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

    test('uploadSnapshot resolves identical server createdTime with deterministic ID tie-breaking', () async {
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
                  'createdTime': '2026-11-06T12:00:00.000Z',
                },
                // Two snapshots with identical createdTime
                <String, dynamic>{
                  'id': 'snap-2a',
                  'name': 'expense-tracker-snapshot-20261105T120000-aaaaaaaaaaaaaaaa.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-05T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-2b',
                  'name': 'expense-tracker-snapshot-20261105T120000-bbbbbbbbbbbbbbbb.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-05T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-4',
                  'name': 'expense-tracker-snapshot-20261103T120000-0000000000000004.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-03T12:00:00.000Z',
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
    });

    test('uploadSnapshot orders by server createdTime despite client clock skew in filename', () async {
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
                // Newly uploaded file has 2020 client clock in name, but server createdTime is 2026-11-06 (latest)
                <String, dynamic>{
                  'id': 'new-file-id',
                  'name': 'expense-tracker-snapshot-20200101T000000-0102030405060708.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-06T12:00:00.000Z',
                },
                // Existing file has 2030 futuristic client clock in name, but server createdTime is 2026-11-04
                <String, dynamic>{
                  'id': 'snap-future-client',
                  'name': 'expense-tracker-snapshot-20300101T000000-0000000000000099.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-04T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-2',
                  'name': 'expense-tracker-snapshot-20261105T120000-0000000000000002.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-05T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-oldest',
                  'name': 'expense-tracker-snapshot-20261103T120000-0000000000000004.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-03T12:00:00.000Z',
                },
              ],
            });
          }
        } else if (req.method == 'POST' && url.path == '/upload/drive/v3/files') {
          return _jsonResponse(<String, dynamic>{'id': 'new-file-id'});
        } else if (req.method == 'GET' && url.path == '/drive/v3/files/new-file-id') {
          return http.Response.bytes(payload, 200);
        } else if (req.method == 'DELETE' && url.path == '/drive/v3/files/snap-oldest') {
          deletedIds.add('snap-oldest');
          return http.Response('', 204);
        }
        return http.Response('Not found', 404);
      });

      // Skewed client clock in 2020
      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
        clock: () => DateTime.utc(2020, 1, 1, 0, 0, 0),
        random: _FixedRandom(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );

      final String uploadedName = await service.uploadSnapshot(payload);
      expect(uploadedName, 'expense-tracker-snapshot-20200101T000000-0102030405060708.json');
      expect(deletedIds, <String>['snap-oldest']);
    });

    test('uploadSnapshot fails closed on missing or invalid createdTime metadata without pruning', () async {
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
                  'createdTime': '2026-11-06T12:00:00.000Z',
                },
                // Snapshot with invalid createdTime string
                <String, dynamic>{
                  'id': 'snap-invalid',
                  'name': 'expense-tracker-snapshot-20261105T120000-aaaaaaaaaaaaaaaa.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': 'not-a-valid-timestamp',
                },
              ],
            });
          }
        } else if (req.method == 'POST' && url.path == '/upload/drive/v3/files') {
          return _jsonResponse(<String, dynamic>{'id': 'new-file-id'});
        } else if (req.method == 'GET' && url.path == '/drive/v3/files/new-file-id') {
          return http.Response.bytes(payload, 200);
        } else if (req.method == 'DELETE') {
          fail('DELETE must not be called when metadata is invalid');
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
            contains('metadata is missing or invalid'),
          ),
        ),
      );
    });

    test('uploadSnapshot fails closed on ambiguous listing with duplicate file IDs', () async {
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
                  'createdTime': '2026-11-06T12:00:00.000Z',
                },
                // Duplicate IDs in candidate listing
                <String, dynamic>{
                  'id': 'dup-id',
                  'name': 'expense-tracker-snapshot-20261105T120000-aaaaaaaaaaaaaaaa.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-05T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'dup-id',
                  'name': 'expense-tracker-snapshot-20261104T120000-bbbbbbbbbbbbbbbb.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-04T12:00:00.000Z',
                },
              ],
            });
          }
        } else if (req.method == 'POST' && url.path == '/upload/drive/v3/files') {
          return _jsonResponse(<String, dynamic>{'id': 'new-file-id'});
        } else if (req.method == 'GET' && url.path == '/drive/v3/files/new-file-id') {
          return http.Response.bytes(payload, 200);
        } else if (req.method == 'DELETE') {
          fail('DELETE must not be called when listing is ambiguous');
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
            contains('listing is ambiguous'),
          ),
        ),
      );
    });

    test('uploadSnapshot fails closed on concurrent writer with newer server createdTime', () async {
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
                // Snapshot from concurrent writer with newer server createdTime
                <String, dynamic>{
                  'id': 'concurrent-newer-id',
                  'name': 'expense-tracker-snapshot-20261106T120500-cccccccccccccccc.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-06T12:05:00.000Z',
                },
                <String, dynamic>{
                  'id': 'new-file-id',
                  'name': 'expense-tracker-snapshot-20261106T120000-0102030405060708.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-06T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-3',
                  'name': 'expense-tracker-snapshot-20261104T120000-0000000000000003.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-04T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-4',
                  'name': 'expense-tracker-snapshot-20261103T120000-0000000000000004.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-03T12:00:00.000Z',
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

    test('uploadSnapshot fails closed on partial pruning failure without deleting new backup', () async {
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
                  'createdTime': '2026-11-06T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-2',
                  'name': 'expense-tracker-snapshot-20261105T120000-0000000000000002.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-05T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-3',
                  'name': 'expense-tracker-snapshot-20261104T120000-0000000000000003.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-04T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-4',
                  'name': 'expense-tracker-snapshot-20261103T120000-0000000000000004.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-03T12:00:00.000Z',
                },
                <String, dynamic>{
                  'id': 'snap-5',
                  'name': 'expense-tracker-snapshot-20261102T120000-0000000000000005.json',
                  'mimeType': 'application/json',
                  'parents': <dynamic>['folder-1'],
                  'ownedByMe': true,
                  'createdTime': '2026-11-02T12:00:00.000Z',
                },
              ],
            });
          }
        } else if (req.method == 'POST' && url.path == '/upload/drive/v3/files') {
          return _jsonResponse(<String, dynamic>{'id': 'new-file-id'});
        } else if (req.method == 'GET' && url.path == '/drive/v3/files/new-file-id') {
          return http.Response.bytes(payload, 200);
        } else if (req.method == 'DELETE') {
          if (url.path == '/drive/v3/files/snap-4') {
            deletedIds.add('snap-4');
            return http.Response('Server Error', 500);
          }
          if (url.path == '/drive/v3/files/new-file-id') {
            fail('Newly uploaded backup must NEVER be deleted during pruning');
          }
        }
        return http.Response('Not found', 404);
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
        clock: () => DateTime.utc(2026, 11, 6, 12, 0, 0),
        random: _FixedRandom(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );

      await expectLater(
        service.uploadSnapshot(payload),
        throwsA(
          isA<BackupException>().having(
            (BackupException e) => e.message,
            'message',
            contains('Snapshot retention pruning failed for file snap-4 (HTTP 500)'),
          ),
        ),
      );
      expect(deletedIds, contains('snap-4'));
      expect(deletedIds, isNot(contains('new-file-id')));
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
                  'createdTime': '2026-11-06T12:00:00.000Z',
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

    test('listOwnedSnapshots orders by server createdTime descending with deterministic ID tie-breaking', () async {
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
            // Name with 2020 client time, but newest createdTime
            <String, dynamic>{
              'id': 'snap-newest-server',
              'name': 'expense-tracker-snapshot-20200101T000000-0000000000000001.json',
              'mimeType': 'application/json',
              'parents': <dynamic>['folder-1'],
              'ownedByMe': true,
              'createdTime': '2026-11-06T12:00:00.000Z',
            },
            // Name with 2030 client time, but second createdTime
            <String, dynamic>{
              'id': 'snap-second-server',
              'name': 'expense-tracker-snapshot-20300101T000000-0000000000000002.json',
              'mimeType': 'application/json',
              'parents': <dynamic>['folder-1'],
              'ownedByMe': true,
              'createdTime': '2026-11-05T12:00:00.000Z',
            },
            // Identical createdTime ties broken deterministically by ID
            <String, dynamic>{
              'id': 'snap-tie-a',
              'name': 'expense-tracker-snapshot-20261104T120000-aaaaaaaaaaaaaaaa.json',
              'mimeType': 'application/json',
              'parents': <dynamic>['folder-1'],
              'ownedByMe': true,
              'createdTime': '2026-11-04T12:00:00.000Z',
            },
            <String, dynamic>{
              'id': 'snap-tie-b',
              'name': 'expense-tracker-snapshot-20261104T120000-bbbbbbbbbbbbbbbb.json',
              'mimeType': 'application/json',
              'parents': <dynamic>['folder-1'],
              'ownedByMe': true,
              'createdTime': '2026-11-04T12:00:00.000Z',
            },
          ],
        });
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
      );

      final List<Map<String, dynamic>> snapshots = await service.listOwnedSnapshots();
      expect(snapshots, hasLength(4));
      expect(snapshots[0]['id'], 'snap-newest-server');
      expect(snapshots[1]['id'], 'snap-second-server');
      expect(snapshots[2]['id'], 'snap-tie-b');
      expect(snapshots[3]['id'], 'snap-tie-a');
    });

    test('listFolder handles pagination and requests createdTime in fields', () async {
      final List<String> requestedFields = <String>[];

      final _FakeClient client = _FakeClient((http.BaseRequest req) async {
        final Uri url = req.url;
        final String q = url.queryParameters['q'] ?? '';
        final String pageToken = url.queryParameters['pageToken'] ?? '';
        final String fields = url.queryParameters['fields'] ?? '';
        requestedFields.add(fields);

        if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
          return _jsonResponse(<String, dynamic>{
            'files': <dynamic>[
              <String, dynamic>{'id': 'folder-1', 'name': 'Expense Tracker'},
            ],
          });
        }

        if (pageToken.isEmpty) {
          return _jsonResponse(<String, dynamic>{
            'nextPageToken': 'token-page-2',
            'files': <dynamic>[
              <String, dynamic>{
                'id': 'snap-page-1',
                'name': 'expense-tracker-snapshot-20261106T120000-0000000000000001.json',
                'mimeType': 'application/json',
                'parents': <dynamic>['folder-1'],
                'ownedByMe': true,
                'createdTime': '2026-11-06T12:00:00.000Z',
              },
            ],
          });
        } else {
          return _jsonResponse(<String, dynamic>{
            'files': <dynamic>[
              <String, dynamic>{
                'id': 'snap-page-2',
                'name': 'expense-tracker-snapshot-20261105T120000-0000000000000002.json',
                'mimeType': 'application/json',
                'parents': <dynamic>['folder-1'],
                'ownedByMe': true,
                'createdTime': '2026-11-05T12:00:00.000Z',
              },
            ],
          });
        }
      });

      final SnapshotDriveService service = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
      );

      final List<Map<String, dynamic>> snapshots = await service.listOwnedSnapshots();
      expect(snapshots, hasLength(2));
      expect(snapshots.map((Map<String, dynamic> f) => f['id']), <String>[
        'snap-page-1',
        'snap-page-2',
      ]);

      // Both folder listing queries (pages 1 and 2) must include createdTime in fields
      final Iterable<String> folderFieldRequests = requestedFields.where(
        (String f) => f.contains('files(id,name,mimeType,parents,ownedByMe'),
      );
      expect(folderFieldRequests, isNotEmpty);
      for (final String fields in folderFieldRequests) {
        expect(fields, contains('createdTime'));
      }
    });

    test('listLegacyMonthlyBackups sorts newest month first', () async {
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
              'id': 'm-sep',
              'name': 'expense-tracker-2026-09.json',
              'mimeType': 'application/json',
              'parents': <dynamic>['folder-1'],
              'ownedByMe': true,
            },
            <String, dynamic>{
              'id': 'm-oct',
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

      final List<Map<String, dynamic>> legacy = await service.listLegacyMonthlyBackups();
      expect(legacy, hasLength(2));
      expect(legacy[0]['id'], 'm-oct');
      expect(legacy[1]['id'], 'm-sep');
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

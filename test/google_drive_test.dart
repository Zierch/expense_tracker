// The Drive half of backup and restore, against a client that answers instead of
// the network.
//
// Nothing here can be seen from outside the app: a wrong query string, a listing
// cut off at the first page, or a lost retry all look like "there was nothing to
// restore" or "export failed" to the user. So the tests pin the requests — the
// folder query, the archive query, paging, `alt=media`, the replaced-file upload —
// and the one retry the access token is allowed.

import 'dart:convert';

import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// An [http.Client] that records every request and answers with [respond].
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.respond);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      respond;

  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return respond(request);
  }
}

http.StreamedResponse _json(Object body, {int status = 200}) {
  final List<int> bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    status,
    contentLength: bytes.length,
  );
}

/// The `q` parameter of a request, or `''`.
String _query(http.BaseRequest request) =>
    request.url.queryParameters['q'] ?? '';

bool _isFolderLookup(http.BaseRequest request) =>
    _query(request).contains("mimeType = 'application/vnd.google-apps.folder'");

/// A Drive holding one folder and the files the handler names.
GoogleDriveService _serviceWith(
  _RecordingClient client, {
  Future<Map<String, String>> Function()? headers,
}) {
  return GoogleDriveService.forTesting(
    client: client,
    headers:
        headers ?? () async => <String, String>{'Authorization': 'Bearer t'},
  );
}

void main() {
  group('listBackupFiles', () {
    test('asks for the app folder, then for the backups inside it', () async {
      final _RecordingClient client =
          _RecordingClient((http.BaseRequest r) async {
        if (_isFolderLookup(r)) {
          return _json(<String, dynamic>{
            'files': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'folder-1', 'name': 'Expense Tracker'},
            ],
          });
        }
        return _json(<String, dynamic>{
          'files': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'file-1',
              'name': 'expense-tracker-2026-10.json',
              'modifiedTime': '2026-10-31T20:00:00.000Z',
            },
          ],
        });
      });

      final List<DriveBackupFile> files =
          await _serviceWith(client).listBackupFiles();

      expect(client.requests, hasLength(2));
      expect(files, hasLength(1));
      expect(files.single.id, 'file-1');
      expect(files.single.name, 'expense-tracker-2026-10.json');
      expect(files.single.modifiedTime, DateTime.utc(2026, 10, 31, 20));

      final http.BaseRequest listing = client.requests.last;
      final String query = _query(listing);
      expect(query, contains("'folder-1' in parents"));
      // Only this app's own month files: the folder may hold anything the user
      // put there, and a restore must not offer it.
      expect(query, contains("name contains 'expense-tracker-'"));
      expect(query, contains("mimeType = 'application/json'"));
      expect(query, contains('trashed = false'));

      expect(listing.url.queryParameters['pageSize'], '100');
      expect(listing.url.queryParameters['orderBy'], 'name desc');
      expect(listing.url.queryParameters['fields'], contains('modifiedTime'));
    });

    test(
        'a Drive that was never exported to answers with nothing, and is not '
        'given a folder behind the user\'s back', () async {
      final _RecordingClient client = _RecordingClient(
        (http.BaseRequest r) async =>
            _json(<String, dynamic>{'files': <dynamic>[]}),
      );

      expect(await _serviceWith(client).listBackupFiles(), isEmpty);
      expect(client.requests, hasLength(1),
          reason: 'only the folder lookup: nothing was created');
    });

    test('follows nextPageToken, so an old month is not cut off', () async {
      int listingCalls = 0;
      final _RecordingClient client =
          _RecordingClient((http.BaseRequest r) async {
        if (_isFolderLookup(r)) {
          return _json(<String, dynamic>{
            'files': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'folder-1', 'name': 'Expense Tracker'},
            ],
          });
        }
        listingCalls++;
        if (listingCalls == 1) {
          expect(r.url.queryParameters.containsKey('pageToken'), isFalse);
          return _json(<String, dynamic>{
            'files': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'a',
                'name': 'expense-tracker-2026-10.json'
              },
            ],
            'nextPageToken': 'page-2',
          });
        }
        expect(r.url.queryParameters['pageToken'], 'page-2');
        return _json(<String, dynamic>{
          'files': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'b',
              'name': 'expense-tracker-2026-09.json'
            },
          ],
        });
      });

      final List<DriveBackupFile> files =
          await _serviceWith(client).listBackupFiles();

      expect(files.map((DriveBackupFile f) => f.id), <String>['a', 'b']);
      expect(listingCalls, 2);
    });
  });

  group('downloadJson', () {
    test('asks for the file itself, not its metadata', () async {
      const String body = '{"app":"Expense Tracker","transactions":[]}';
      final _RecordingClient client = _RecordingClient(
        (http.BaseRequest r) async => _json(jsonDecode(body)),
      );

      // An id with a space and a slash, which is what encoding has to survive.
      expect(await _serviceWith(client).downloadJson('a b/c'), body);

      final Uri url = client.requests.single.url;
      expect(url.toString(), contains('a%20b%2Fc'));
      expect(url.queryParameters['alt'], 'media');
    });

    test('an expired token is refreshed once, then the read succeeds',
        () async {
      int tokens = 0;
      final _RecordingClient client =
          _RecordingClient((http.BaseRequest r) async {
        if (r.headers['Authorization'] == 'Bearer 1') {
          return _json(<String, dynamic>{
            'error': <String, dynamic>{'message': 'Invalid Credentials'},
          }, status: 401);
        }
        return _json(<String, dynamic>{'app': 'Expense Tracker'});
      });

      final String text = await _serviceWith(
        client,
        headers: () async =>
            <String, String>{'Authorization': 'Bearer ${++tokens}'},
      ).downloadJson('file-1');

      expect(text, contains('Expense Tracker'));
      expect(client.requests, hasLength(2));
      expect(client.requests.last.headers['Authorization'], 'Bearer 2');
    });

    test('a second 401 says what to do instead of retrying forever', () async {
      final _RecordingClient client = _RecordingClient(
        (http.BaseRequest r) async => _json(<String, dynamic>{}, status: 401),
      );

      await expectLater(
        _serviceWith(client).downloadJson('file-1'),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('Sign out and sign in again'),
        )),
      );
      expect(client.requests, hasLength(2));
    });

    test(
        'a file larger than a month backup can be is refused before reading it',
        () async {
      final _RecordingClient client = _RecordingClient(
        (http.BaseRequest r) async => http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('{}')),
          200,
          // What the server declares wins over what it then sends.
          contentLength: 11 * 1024 * 1024,
        ),
      );

      await expectLater(
        _serviceWith(client).downloadJson('file-1'),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('larger than 10 MB'),
        )),
      );
    });

    test('a Drive error carries the server\'s own explanation', () async {
      final _RecordingClient client = _RecordingClient(
        (http.BaseRequest r) async => _json(<String, dynamic>{
          'error': <String, dynamic>{'message': 'File not found: nope'},
        }, status: 404),
      );

      await expectLater(
        _serviceWith(client).downloadJson('nope'),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          allOf(contains('HTTP 404'), contains('File not found: nope')),
        )),
      );
    });
  });

  group('uploadJson', () {
    test('replaces the month that is already there instead of adding a copy',
        () async {
      final _RecordingClient client =
          _RecordingClient((http.BaseRequest r) async {
        if (_isFolderLookup(r)) {
          return _json(<String, dynamic>{
            'files': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'folder-1'},
            ],
          });
        }
        if (_query(r).contains("name = 'expense-tracker-2026-10.json'")) {
          return _json(<String, dynamic>{
            'files': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'existing-file'},
            ],
          });
        }
        return _json(<String, dynamic>{
          'id': 'existing-file',
          'name': 'expense-tracker-2026-10.json',
        });
      });

      final DriveUploadResult result = await _serviceWith(client).uploadJson(
        fileName: 'expense-tracker-2026-10.json',
        data: <String, dynamic>{'app': 'Expense Tracker'},
      );

      expect(result.replacedExisting, isTrue);
      final http.BaseRequest upload = client.requests.last;
      expect(upload.method, 'PATCH');
      expect(upload.url.toString(), contains('existing-file'));
      expect(upload.url.queryParameters['uploadType'], 'media');
    });

    test('an expired token is refreshed once, and the upload is not repeated '
        'from the start', () async {
      int tokens = 0;
      int uploads = 0;
      final _RecordingClient client = _RecordingClient((http.BaseRequest r) async {
        if (_isFolderLookup(r)) {
          return _json(<String, dynamic>{
            'files': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'folder-1'},
            ],
          });
        }
        if (_query(r).contains("name = 'expense-tracker-2026-10.json'")) {
          return _json(<String, dynamic>{
            'files': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'existing-file'},
            ],
          });
        }
        uploads++;
        if (r.headers['Authorization'] == 'Bearer 1') {
          return _json(<String, dynamic>{}, status: 401);
        }
        return _json(<String, dynamic>{
          'id': 'existing-file',
          'name': 'expense-tracker-2026-10.json',
        });
      });

      final DriveUploadResult result = await _serviceWith(
        client,
        headers: () async => <String, String>{'Authorization': 'Bearer ${++tokens}'},
      ).uploadJson(
        fileName: 'expense-tracker-2026-10.json',
        data: <String, dynamic>{'app': 'Expense Tracker'},
      );

      expect(result.replacedExisting, isTrue);
      expect(uploads, 2, reason: 'one refusal, one retry — not a loop');
      expect(client.requests.last.headers['Authorization'], 'Bearer 2');
    });

    test('a month that is not there yet is created in one request', () async {
      final _RecordingClient client =
          _RecordingClient((http.BaseRequest r) async {
        if (_isFolderLookup(r)) {
          return _json(<String, dynamic>{
            'files': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'folder-1'},
            ],
          });
        }
        if (_query(r).contains("name = 'expense-tracker-2026-11.json'")) {
          return _json(<String, dynamic>{'files': <dynamic>[]});
        }
        return _json(<String, dynamic>{
          'id': 'new-file',
          'name': 'expense-tracker-2026-11.json',
        });
      });

      final DriveUploadResult result = await _serviceWith(client).uploadJson(
        fileName: 'expense-tracker-2026-11.json',
        data: <String, dynamic>{'app': 'Expense Tracker'},
      );

      expect(result.replacedExisting, isFalse);
      final http.BaseRequest upload = client.requests.last;
      expect(upload.method, 'POST');
      expect(upload.url.queryParameters['uploadType'], 'multipart');
      // The file is filed under the folder the app owns, not at the root.
      expect(utf8.decode((upload as http.Request).bodyBytes),
          contains('"parents":["folder-1"]'));
    });
  });
}

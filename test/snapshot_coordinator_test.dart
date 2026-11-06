import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:expense_tracker/data/services/google_drive_service.dart'
    show BackupException;
import 'package:expense_tracker/data/services/snapshot_coordinator.dart';
import 'package:expense_tracker/data/services/snapshot_drive_service.dart';
import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/usecases/export_snapshot_usecase.dart';
import 'package:expense_tracker/domain/usecases/import_snapshot_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _DummyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnimplementedError('Unexpected HTTP request: ${request.url}');
  }
}

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

class _FakeSnapshotDriveService extends SnapshotDriveService {
  _FakeSnapshotDriveService({
    this.snapshots = const <Map<String, dynamic>>[],
    this.legacyFiles = const <Map<String, dynamic>>[],
    this.fileContents = const <String, String>{},
    this.failUpload = false,
    this.downloadCompleter,
  }) : super(
          client: _DummyClient(),
          headers: () async => <String, String>{},
        );

  final List<Map<String, dynamic>> snapshots;
  final List<Map<String, dynamic>> legacyFiles;
  final Map<String, String> fileContents;
  final List<String> downloadedFileIds = <String>[];
  final List<String> deletedFileIds = <String>[];
  bool uploadSnapshotCalled = false;
  List<int>? lastUploadedBytes;
  bool failUpload;
  Completer<void>? downloadCompleter;

  @override
  Future<List<Map<String, dynamic>>> listOwnedSnapshots({String? folderName}) async {
    return List<Map<String, dynamic>>.from(snapshots);
  }

  @override
  Future<List<Map<String, dynamic>>> listLegacyMonthlyBackups({String? folderName}) async {
    return List<Map<String, dynamic>>.from(legacyFiles);
  }

  @override
  Future<List<int>> downloadFile(String fileId) async {
    if (downloadCompleter != null) {
      await downloadCompleter!.future;
    }
    downloadedFileIds.add(fileId);
    final String? content = fileContents[fileId];
    if (content == null) {
      throw BackupException('File not found in fake storage: $fileId');
    }
    return utf8.encode(content);
  }

  @override
  Future<String> uploadSnapshot(List<int> bytes, {String? folderName}) async {
    if (failUpload) {
      throw BackupException('Simulated network error during snapshot upload');
    }
    uploadSnapshotCalled = true;
    lastUploadedBytes = bytes;
    return 'uploaded-snapshot.json';
  }
}

class _MockTransactionRepository implements TransactionRepository {
  final List<TransactionEntity> transactions = <TransactionEntity>[];
  int importCalls = 0;
  bool throwOnImport = false;

  @override
  Future<ImportWriteResult> importTransactions(
      List<ImportTransaction> rows) async {
    importCalls++;
    if (throwOnImport) {
      throw StateError('Simulated database write error during import');
    }

    int imported = 0;
    int duplicates = 0;

    for (final ImportTransaction row in rows) {
      final bool exists = transactions.any((TransactionEntity t) =>
          t.date == row.date &&
          t.type == row.type &&
          t.amount == row.amount &&
          t.categoryName == row.categoryName &&
          t.subcategoryName == row.subcategoryName &&
          t.note == row.note);

      if (exists) {
        duplicates++;
      } else {
        imported++;
        transactions.add(TransactionEntity(
          id: transactions.length + 1,
          type: row.type,
          amount: row.amount,
          categoryId: 1,
          subcategoryId: row.subcategoryName != null ? 1 : null,
          categoryName: row.categoryName,
          subcategoryName: row.subcategoryName,
          note: row.note,
          date: row.date,
          createdAt: row.date,
        ));
      }
    }

    return ImportWriteResult(imported: imported, duplicates: duplicates);
  }

  @override
  Future<List<TransactionEntity>> getAllTransactions() async =>
      List<TransactionEntity>.from(transactions);

  @override
  Stream<List<TransactionEntity>> watchAllTransactions() =>
      Stream<List<TransactionEntity>>.value(transactions);

  @override
  Future<List<TransactionEntity>> getTransactionsByDateRange(
      DateTime start, DateTime end) async {
    return transactions.where((TransactionEntity t) {
      return !t.date.isBefore(start) && !t.date.isAfter(end);
    }).toList();
  }

  @override
  Future<List<DateTime>> getMonthsWithTransactions() async {
    final Set<int> keys = <int>{};
    for (final TransactionEntity t in transactions) {
      keys.add(t.date.year * 12 + t.date.month - 1);
    }
    return (keys.toList()..sort())
        .map((int key) => DateTime(key ~/ 12, key % 12 + 1))
        .toList();
  }

  @override
  Future<double> getTotalIncome({DateTime? start, DateTime? end}) async =>
      _totalFor('income', start: start, end: end);

  @override
  Future<double> getTotalExpense({DateTime? start, DateTime? end}) async =>
      _totalFor('expense', start: start, end: end);

  @override
  Future<Map<String, double>> getIncomeByCategory(
      {DateTime? start, DateTime? end}) async =>
      _breakdownFor('income', start: start, end: end);

  @override
  Future<Map<String, double>> getExpenseByCategory(
      {DateTime? start, DateTime? end}) async =>
      _breakdownFor('expense', start: start, end: end);

  @override
  Future<int> insertTransaction(TransactionEntity transaction) async {
    transactions.add(transaction);
    return transaction.id;
  }

  @override
  Future<bool> updateTransaction(TransactionEntity transaction) async => true;

  @override
  Future<int> deleteTransaction(int id) async {
    transactions.removeWhere((TransactionEntity t) => t.id == id);
    return 1;
  }

  double _totalFor(String type, {DateTime? start, DateTime? end}) {
    return transactions
        .where((TransactionEntity t) =>
            t.type == type &&
            (start == null || !t.date.isBefore(start)) &&
            (end == null || !t.date.isAfter(end)))
        .fold<double>(0.0, (double sum, TransactionEntity t) => sum + t.amount);
  }

  Map<String, double> _breakdownFor(String type,
      {DateTime? start, DateTime? end}) {
    final Map<String, double> map = <String, double>{};
    for (final TransactionEntity t in transactions.where((TransactionEntity t) =>
        t.type == type &&
        (start == null || !t.date.isBefore(start)) &&
        (end == null || !t.date.isAfter(end)))) {
      final String category = t.categoryName ?? 'Uncategorized';
      map[category] = (map[category] ?? 0.0) + t.amount;
    }
    return map;
  }
}

String _monthlyJson({
  required int year,
  required int month,
  required List<Map<String, dynamic>> transactions,
  String app = 'Expense Tracker',
  num schemaVersion = 1,
}) {
  final String monthStr = month.toString().padLeft(2, '0');
  return jsonEncode(<String, dynamic>{
    'app': app,
    'schemaVersion': schemaVersion,
    'currency': 'IDR',
    'exportedAt': '$year-$monthStr-28T12:00:00',
    'period': <String, dynamic>{
      'year': year,
      'month': month,
      'startDate': '$year-$monthStr-01',
      'endDate': '$year-$monthStr-28',
    },
    'summary': <String, dynamic>{
      'totalIncome': 0.0,
      'totalExpense': 0.0,
      'balance': 0.0,
      'incomeByCategory': <dynamic>[],
      'expenseByCategory': <dynamic>[],
    },
    'transactions': transactions,
  });
}

String _snapshotJson({
  required List<Map<String, dynamic>> transactions,
  String app = 'Expense Tracker',
  String backupType = 'snapshot',
  num schemaVersion = 2,
  double totalIncome = 1000000.0,
  double totalExpense = 500000.0,
}) {
  return jsonEncode(<String, dynamic>{
    'app': app,
    'schemaVersion': schemaVersion,
    'backupType': backupType,
    'currency': 'IDR',
    'exportedAt': '2026-11-06T12:00:00',
    'period': <String, dynamic>{
      'type': 'all',
      'monthCount': 1,
      'startDate': '2026-10-01',
      'endDate': '2026-10-31',
    },
    'summary': <String, dynamic>{
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
      'balance': totalIncome - totalExpense,
      'incomeByCategory': <Map<String, dynamic>>[],
      'expenseByCategory': <Map<String, dynamic>>[],
    },
    'transactions': transactions,
  });
}

Map<String, dynamic> _row({
  int id = 1,
  String date = '2026-10-15',
  String type = 'expense',
  String category = 'Food',
  String? subcategory = 'Groceries',
  Object? amount = 150000.0,
  String? note = 'Weekly market',
}) {
  return <String, dynamic>{
    'id': id,
    'date': date,
    'createdAt': '2026-10-15T12:30:45.000Z',
    'type': type,
    'category': category,
    'subcategory': subcategory,
    'amount': amount,
    'note': note,
  };
}

SnapshotCoordinator _createCoordinator({
  required SnapshotDriveService drive,
  required _MockTransactionRepository repo,
}) {
  final ExportSnapshotUseCase exporter = ExportSnapshotUseCase(repo);
  final ImportSnapshotUseCase importer = ImportSnapshotUseCase(repo);
  return SnapshotCoordinator(drive, exporter, importer);
}

void main() {
  group('SnapshotCoordinator - Backup', () {
    test(
        'backup creates full snapshot schema 2 and uploads to Drive without monthly migration',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      await repo.insertTransaction(TransactionEntity(
        id: 1,
        type: 'income',
        amount: 5000000.0,
        categoryId: 1,
        subcategoryId: null,
        categoryName: 'Salary',
        subcategoryName: null,
        note: 'Monthly salary',
        date: DateTime(2026, 10, 15),
        createdAt: DateTime(2026, 10, 15),
      ));

      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[],
        legacyFiles: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'legacy-1',
            'name': 'expense-tracker-2026-10.json',
          },
        ],
        fileContents: <String, String>{
          'legacy-1': _monthlyJson(
            year: 2026,
            month: 10,
            transactions: <Map<String, dynamic>>[
              _row(
                date: '2026-10-15',
                type: 'income',
                category: 'LegacySalary',
                amount: 9999999.0,
                note: 'Should not be imported',
              ),
            ],
          ),
        },
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      final String uploadedName = await coordinator.backup();

      expect(uploadedName, 'uploaded-snapshot.json');
      // Monthly migration is discarded: 0 import calls, local transactions unchanged
      expect(repo.importCalls, 0);
      expect(repo.transactions, hasLength(1));
      expect(repo.transactions.first.categoryName, 'Salary');
      expect(repo.transactions.first.amount, 5000000.0);
      expect(drive.uploadSnapshotCalled, isTrue);
      // Legacy files on Drive were NOT downloaded
      expect(drive.downloadedFileIds, isEmpty);
      expect(drive.lastUploadedBytes, isNotNull);

      final Map<String, dynamic> uploadedJson = jsonDecode(
        utf8.decode(drive.lastUploadedBytes!),
      ) as Map<String, dynamic>;
      expect(uploadedJson['app'], 'Expense Tracker');
      expect(uploadedJson['backupType'], 'snapshot');
      expect(uploadedJson['schemaVersion'], 2);
      final List<dynamic> txs = uploadedJson['transactions'] as List<dynamic>;
      expect(txs, hasLength(1));
      expect(txs.first['category'], 'Salary');
    });

    test(
        'existing snapshots skip monthly migration and uploads local repository snapshot',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      await repo.insertTransaction(TransactionEntity(
        id: 1,
        type: 'expense',
        amount: 85000.0,
        categoryId: 1,
        subcategoryId: null,
        categoryName: 'LocalExpense',
        subcategoryName: null,
        note: 'Pre-existing local transaction',
        date: DateTime(2026, 11, 1),
        createdAt: DateTime(2026, 11, 1),
      ));

      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'snap-existing',
            'name': 'expense-tracker-snapshot-20261101T000000-0123456789abcdef.json',
            'ownedByMe': true,
          },
        ],
        legacyFiles: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'legacy-old',
            'name': 'expense-tracker-2026-09.json',
          },
        ],
        fileContents: <String, String>{
          'legacy-old': _monthlyJson(
            year: 2026,
            month: 9,
            transactions: <Map<String, dynamic>>[
              _row(category: 'LegacyIgnoredCategory'),
            ],
          ),
        },
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      final String uploadedName = await coordinator.backup();

      expect(uploadedName, 'uploaded-snapshot.json');
      expect(repo.importCalls, 0);
      expect(repo.transactions, hasLength(1));
      expect(repo.transactions.first.categoryName, 'LocalExpense');
      expect(drive.downloadedFileIds, isEmpty);
      expect(drive.uploadSnapshotCalled, isTrue);

      final Map<String, dynamic> uploadedJson = jsonDecode(
        utf8.decode(drive.lastUploadedBytes!),
      ) as Map<String, dynamic>;
      expect(uploadedJson['backupType'], 'snapshot');
      expect(uploadedJson['schemaVersion'], 2);
      final List<dynamic> txs = uploadedJson['transactions'] as List<dynamic>;
      expect(txs, hasLength(1));
      expect(txs.first['category'], 'LocalExpense');
    });

    test('failed upload in backup propagates error and releases busy guard',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[],
        legacyFiles: const <Map<String, dynamic>>[],
        failUpload: true,
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      await expectLater(
        coordinator.backup(),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('Simulated network error during snapshot upload'),
        )),
      );

      expect(drive.uploadSnapshotCalled, isFalse);

      // Verify busy guard was cleanly released in finally block
      drive.failUpload = false;
      final String uploadedName = await coordinator.backup();
      expect(uploadedName, 'uploaded-snapshot.json');
      expect(drive.uploadSnapshotCalled, isTrue);
    });

    test(
        'backup integrates with existing Drive service retaining latest 3 versions and preserving remote legacy files',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      await repo.insertTransaction(TransactionEntity(
        id: 1,
        type: 'income',
        amount: 3000000.0,
        categoryId: 1,
        subcategoryId: null,
        categoryName: 'Consulting',
        subcategoryName: null,
        note: 'Client project',
        date: DateTime(2026, 11, 6),
        createdAt: DateTime(2026, 11, 6),
      ));

      final List<String> deletedIds = <String>[];
      List<int>? capturedPayload;

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
                // Legacy monthly file - existing remote file that MUST NOT be deleted
                <String, dynamic>{
                  'id': 'legacy-remote-1',
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
          if (req is http.Request) {
            final String text = utf8.decode(req.bodyBytes);
            const String marker = 'Content-Type: application/json\r\n\r\n';
            final int payloadMarker = text.indexOf(marker);
            if (payloadMarker != -1) {
              final int payloadStart = payloadMarker + marker.length;
              final int payloadEnd = text.lastIndexOf('\r\n--');
              capturedPayload = utf8.encode(text.substring(payloadStart, payloadEnd));
            }
          }
          return _jsonResponse(<String, dynamic>{'id': 'new-file-id'});
        } else if (req.method == 'GET' && url.path == '/drive/v3/files/new-file-id') {
          return http.Response.bytes(capturedPayload!, 200);
        } else if (req.method == 'DELETE' && url.path == '/drive/v3/files/snap-4') {
          deletedIds.add('snap-4');
          return http.Response('', 204);
        }
        return http.Response('Not found', 404);
      });

      final SnapshotDriveService drive = SnapshotDriveService(
        client: client,
        headers: () async => <String, String>{'Authorization': 'Bearer test-token'},
        clock: () => DateTime.utc(2026, 11, 6, 12, 0, 0),
        random: _FixedRandom(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      final String uploadedName = await coordinator.backup();
      expect(uploadedName, 'expense-tracker-snapshot-20261106T120000-0102030405060708.json');

      // 3-version safety: kept latest 3 owned snapshots (new-file-id, snap-2, snap-3), pruned 4th (snap-4)
      expect(deletedIds, <String>['snap-4']);
      // Remote legacy monthly file was NOT deleted
      expect(deletedIds.contains('legacy-remote-1'), isFalse);

      // Verify uploaded snapshot payload is schema 2
      expect(capturedPayload, isNotNull);
      final Map<String, dynamic> decoded =
          jsonDecode(utf8.decode(capturedPayload!)) as Map<String, dynamic>;
      expect(decoded['app'], 'Expense Tracker');
      expect(decoded['backupType'], 'snapshot');
      expect(decoded['schemaVersion'], 2);
      final List<dynamic> txs = decoded['transactions'] as List<dynamic>;
      expect(txs, hasLength(1));
      expect(txs.first['category'], 'Consulting');
    });

    test(
        'coordinator supports legacy 4-argument constructor without performing migration',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      await repo.insertTransaction(TransactionEntity(
        id: 1,
        type: 'income',
        amount: 250000.0,
        categoryId: 1,
        subcategoryId: null,
        categoryName: 'Freelance',
        subcategoryName: null,
        note: 'Contract work',
        date: DateTime(2026, 11, 2),
        createdAt: DateTime(2026, 11, 2),
      ));
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService();
      final ExportSnapshotUseCase exporter = ExportSnapshotUseCase(repo);
      final ImportSnapshotUseCase importer = ImportSnapshotUseCase(repo);
      final SnapshotCoordinator coordinator =
          SnapshotCoordinator(drive, exporter, importer);

      final String uploaded = await coordinator.backup();
      expect(uploaded, 'uploaded-snapshot.json');
      expect(drive.uploadSnapshotCalled, isTrue);
      expect(repo.importCalls, 0);
    });
  });

  group('SnapshotCoordinator - Sync and Validation', () {
    test('sync throws and does not write when no snapshots exist', () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[],
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      expect(
        () => coordinator.sync(),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('No snapshot found.'),
        )),
      );

      expect(repo.importCalls, 0);
      expect(repo.transactions, isEmpty);
    });

    test('sync throws and does not write when snapshot metadata id is invalid or empty',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[
          <String, dynamic>{'id': '', 'name': 'invalid-snapshot.json'},
        ],
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      expect(
        () => coordinator.sync(),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('Snapshot metadata is invalid.'),
        )),
      );

      expect(repo.importCalls, 0);
      expect(repo.transactions, isEmpty);
    });

    test('sync throws and does not write when latest snapshot has invalid app',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[
          <String, dynamic>{'id': 'snap-1', 'name': 'snapshot.json'},
        ],
        fileContents: <String, String>{
          'snap-1': _snapshotJson(
            app: 'WrongApp',
            transactions: <Map<String, dynamic>>[_row()],
          ),
        },
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      expect(
        () => coordinator.sync(),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('Latest snapshot is invalid or unsupported. No data was imported.'),
        )),
      );

      expect(repo.importCalls, 0);
      expect(repo.transactions, isEmpty);
    });

    test('sync throws and does not write when latest snapshot has invalid backupType',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[
          <String, dynamic>{'id': 'snap-1', 'name': 'snapshot.json'},
        ],
        fileContents: <String, String>{
          'snap-1': _snapshotJson(
            backupType: 'monthly',
            transactions: <Map<String, dynamic>>[_row()],
          ),
        },
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      expect(
        () => coordinator.sync(),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('Latest snapshot is invalid or unsupported. No data was imported.'),
        )),
      );

      expect(repo.importCalls, 0);
      expect(repo.transactions, isEmpty);
    });

    test('sync throws and does not write when latest snapshot has unsupported schemaVersion',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[
          <String, dynamic>{'id': 'snap-1', 'name': 'snapshot.json'},
        ],
        fileContents: <String, String>{
          'snap-1': _snapshotJson(
            schemaVersion: 3,
            transactions: <Map<String, dynamic>>[_row()],
          ),
        },
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      expect(
        () => coordinator.sync(),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('Latest snapshot is invalid or unsupported. No data was imported.'),
        )),
      );

      expect(repo.importCalls, 0);
      expect(repo.transactions, isEmpty);
    });

    test('sync throws and does not write when latest snapshot has legacy schemaVersion 1',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[
          <String, dynamic>{'id': 'snap-1', 'name': 'snapshot.json'},
        ],
        fileContents: <String, String>{
          'snap-1': _snapshotJson(
            schemaVersion: 1,
            transactions: <Map<String, dynamic>>[_row()],
          ),
        },
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      expect(
        () => coordinator.sync(),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('Latest snapshot is invalid or unsupported. No data was imported.'),
        )),
      );

      expect(repo.importCalls, 0);
      expect(repo.transactions, isEmpty);
    });

    test('sync throws and does not write when latest snapshot contains unreadable row under strict mode',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[
          <String, dynamic>{'id': 'snap-1', 'name': 'snapshot.json'},
        ],
        fileContents: <String, String>{
          'snap-1': _snapshotJson(
            transactions: <Map<String, dynamic>>[
              _row(date: '2026-10-15', amount: 100000.0),
              _row(date: '2026-10-16', amount: -50000.0), // Invalid amount
            ],
          ),
        },
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      expect(
        () => coordinator.sync(),
        throwsA(isA<SnapshotImportException>().having(
          (SnapshotImportException e) => e.message,
          'message',
          contains('Backup contains 1 invalid transaction(s). No data was imported.'),
        )),
      );

      expect(repo.importCalls, 0);
      expect(repo.transactions, isEmpty);
    });

    test('repeated sync is idempotent and preserves local transaction count',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[
          <String, dynamic>{'id': 'snap-1', 'name': 'snapshot.json'},
        ],
        fileContents: <String, String>{
          'snap-1': _snapshotJson(
            transactions: <Map<String, dynamic>>[
              _row(date: '2026-10-10', amount: 120000.0, note: 'Item 1'),
              _row(date: '2026-10-12', amount: 340000.0, note: 'Item 2'),
            ],
          ),
        },
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      // First sync imports 2 rows
      final SnapshotImportResult first = await coordinator.sync();
      expect(first.imported, 2);
      expect(first.duplicates, 0);
      expect(repo.importCalls, 1);
      expect(repo.transactions, hasLength(2));

      // Repeated sync runs without error, detecting 2 duplicates and 0 new inserts
      final SnapshotImportResult second = await coordinator.sync();
      expect(second.imported, 0);
      expect(second.duplicates, 2);
      expect(repo.importCalls, 2);
      expect(repo.transactions, hasLength(2));
    });

    test('concurrent sync or backup throws BackupException when operation is already running',
        () async {
      final Completer<void> downloadCompleter = Completer<void>();
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[
          <String, dynamic>{'id': 'snap-1', 'name': 'snapshot.json'},
        ],
        fileContents: <String, String>{
          'snap-1': _snapshotJson(
            transactions: <Map<String, dynamic>>[_row()],
          ),
        },
        downloadCompleter: downloadCompleter,
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      // Launch sync that pauses during download
      final Future<SnapshotImportResult> inFlightSync = coordinator.sync();
      await Future<void>.delayed(Duration.zero);

      // Concurrent sync attempt while busy
      expect(
        () => coordinator.sync(),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('A backup or sync is already running.'),
        )),
      );

      // Concurrent backup attempt while busy
      expect(
        () => coordinator.backup(),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('A backup or sync is already running.'),
        )),
      );

      // Unblock download
      downloadCompleter.complete();
      final SnapshotImportResult result = await inFlightSync;
      expect(result.imported, 1);

      // Subsequent operation after completion succeeds
      final SnapshotImportResult followUp = await coordinator.sync();
      expect(followUp.duplicates, 1);
    });

    test(
        'sync imports latest snapshot when multiple snapshot versions exist and ignores legacy files',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'snap-latest',
            'name': 'expense-tracker-snapshot-20261106T120000-0000000000000001.json',
            'createdTime': '2026-11-06T12:00:00.000Z',
          },
          <String, dynamic>{
            'id': 'snap-older',
            'name': 'expense-tracker-snapshot-20261105T120000-0000000000000002.json',
            'createdTime': '2026-11-05T12:00:00.000Z',
          },
          <String, dynamic>{
            'id': 'snap-oldest',
            'name': 'expense-tracker-snapshot-20261104T120000-0000000000000003.json',
            'createdTime': '2026-11-04T12:00:00.000Z',
          },
        ],
        legacyFiles: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'legacy-remote',
            'name': 'expense-tracker-2026-10.json',
          },
        ],
        fileContents: <String, String>{
          'snap-latest': _snapshotJson(
            transactions: <Map<String, dynamic>>[
              _row(date: '2026-11-06', amount: 500000.0, note: 'Latest'),
            ],
          ),
          'snap-older': _snapshotJson(
            transactions: <Map<String, dynamic>>[
              _row(date: '2026-11-05', amount: 200000.0, note: 'Older'),
            ],
          ),
          'snap-oldest': _snapshotJson(
            transactions: <Map<String, dynamic>>[
              _row(date: '2026-11-04', amount: 100000.0, note: 'Oldest'),
            ],
          ),
        },
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      final SnapshotImportResult result = await coordinator.sync();
      expect(result.imported, 1);
      expect(repo.transactions, hasLength(1));
      expect(repo.transactions.first.amount, 500000.0);
      expect(repo.transactions.first.note, 'Latest');

      // Only the latest snapshot file was downloaded; older snapshots and legacy files were untouched
      expect(drive.downloadedFileIds, <String>['snap-latest']);
    });
  });
}

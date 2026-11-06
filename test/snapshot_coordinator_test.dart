import 'dart:async';
import 'dart:convert';

import 'package:expense_tracker/data/services/google_drive_service.dart'
    show BackupException;
import 'package:expense_tracker/data/services/snapshot_coordinator.dart';
import 'package:expense_tracker/data/services/snapshot_drive_service.dart';
import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/usecases/export_snapshot_usecase.dart';
import 'package:expense_tracker/domain/usecases/import_snapshot_usecase.dart';
import 'package:expense_tracker/domain/usecases/legacy_migration_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _DummyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnimplementedError('Unexpected HTTP request: ${request.url}');
  }
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
  num schemaVersion = 1,
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
    'type': type,
    'category': category,
    'subcategory': subcategory,
    'amount': amount,
    'note': note,
  };
}

SnapshotCoordinator _createCoordinator({
  required _FakeSnapshotDriveService drive,
  required _MockTransactionRepository repo,
}) {
  final ExportSnapshotUseCase exporter = ExportSnapshotUseCase(repo);
  final ImportSnapshotUseCase importer = ImportSnapshotUseCase(repo);
  final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
    repository: repo,
    driveService: drive,
    exportSnapshotUseCase: exporter,
  );
  return SnapshotCoordinator(drive, migration, exporter, importer);
}

void main() {
  group('SnapshotCoordinator - Backup and Migration', () {
    test('no snapshots triggers legacy migration and uploads prepared snapshot',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
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
                category: 'Salary',
                amount: 5000000.0,
                note: 'Monthly salary',
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
      expect(repo.importCalls, 1);
      expect(repo.transactions, hasLength(1));
      expect(repo.transactions.first.categoryName, 'Salary');
      expect(repo.transactions.first.amount, 5000000.0);
      expect(drive.uploadSnapshotCalled, isTrue);
      expect(drive.downloadedFileIds, <String>['legacy-1']);
      expect(drive.lastUploadedBytes, isNotNull);

      final Map<String, dynamic> uploadedJson = jsonDecode(
        utf8.decode(drive.lastUploadedBytes!),
      ) as Map<String, dynamic>;
      expect(uploadedJson['app'], 'Expense Tracker');
      expect(uploadedJson['backupType'], 'snapshot');
      expect(uploadedJson['schemaVersion'], 1);
      final List<dynamic> txs = uploadedJson['transactions'] as List<dynamic>;
      expect(txs, hasLength(1));
      expect(txs.first['category'], 'Salary');
    });

    test(
        'existing snapshots skip legacy migration and uploads local repository snapshot',
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
      // Migration skipped to avoid resurrecting deletions
      expect(repo.importCalls, 0);
      expect(repo.transactions, hasLength(1));
      expect(repo.transactions.first.categoryName, 'LocalExpense');
      expect(drive.downloadedFileIds, isEmpty);
      expect(drive.uploadSnapshotCalled, isTrue);

      final Map<String, dynamic> uploadedJson = jsonDecode(
        utf8.decode(drive.lastUploadedBytes!),
      ) as Map<String, dynamic>;
      expect(uploadedJson['backupType'], 'snapshot');
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

      expect(
        () => coordinator.backup(),
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
        'failed upload during legacy migration preserves imported data and retry succeeds idempotently',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
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
              _row(date: '2026-10-15', amount: 150000.0, note: 'Market'),
            ],
          ),
        },
        failUpload: true,
      );

      final SnapshotCoordinator coordinator = _createCoordinator(
        drive: drive,
        repo: repo,
      );

      // First backup fails at upload step after migration execution
      await expectLater(
        coordinator.backup(),
        throwsA(isA<BackupException>()),
      );
      expect(repo.importCalls, 1);
      expect(repo.transactions, hasLength(1));

      // Retry backup with upload restored: imports 0 duplicates and uploads snapshot successfully
      drive.failUpload = false;
      final String uploadedName = await coordinator.backup();
      expect(uploadedName, 'uploaded-snapshot.json');
      expect(repo.importCalls, 2);
      expect(repo.transactions, hasLength(1)); // No duplicate rows created
      expect(drive.uploadSnapshotCalled, isTrue);
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
          contains('No snapshot found. Back up all data to migrate older backups first.'),
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
            schemaVersion: 2,
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
  });
}

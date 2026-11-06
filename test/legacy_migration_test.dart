import 'dart:convert';

import 'package:drift/native.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/transaction_repository_impl.dart';
import 'package:expense_tracker/data/services/google_drive_service.dart'
    show BackupException;
import 'package:expense_tracker/data/services/snapshot_drive_service.dart';
import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/usecases/export_snapshot_usecase.dart';
import 'package:expense_tracker/domain/usecases/legacy_migration_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'sqlite_support.dart';

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
    downloadedFileIds.add(fileId);
    final String? content = fileContents[fileId];
    if (content == null) {
      throw BackupException('File not found in fake storage: $fileId');
    }
    return utf8.encode(content);
  }

  @override
  Future<String> uploadSnapshot(List<int> bytes, {String? folderName}) async {
    uploadSnapshotCalled = true;
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
      map[t.categoryName] = (map[t.categoryName] ?? 0.0) + t.amount;
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

Map<String, dynamic> _row({
  String date = '2026-10-15',
  String type = 'expense',
  String category = 'Food',
  String? subcategory = 'Groceries',
  Object? amount = 150000.0,
  String? note = 'Weekly market',
}) {
  return <String, dynamic>{
    'id': 1,
    'date': date,
    'type': type,
    'category': category,
    'subcategory': subcategory,
    'amount': amount,
    'note': note,
  };
}

void main() {
  group('LegacyMigrationUseCase - Dry-Run Validation and Preconditions', () {
    test('avoids resurrecting deletions by skipping when snapshots exist',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'snap-1',
            'name': 'expense-tracker-snapshot-20261101T000000-0123456789abcdef.json',
            'ownedByMe': true,
          },
        ],
        legacyFiles: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'legacy-1',
            'name': 'expense-tracker-2026-10.json',
          },
        ],
        fileContents: <String, String>{
          'legacy-1': _monthlyJson(
            year: 2026,
            month: 10,
            transactions: <Map<String, dynamic>>[_row()],
          ),
        },
      );

      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
        driveService: drive,
      );

      final MigrationResult result = await migration.autoMigrate();

      expect(result.status, MigrationStatus.skippedSnapshotsExist);
      expect(result.isSkipped, isTrue);
      expect(result.filesProcessed, 0);
      expect(result.importedCount, 0);
      expect(repo.importCalls, 0);
      expect(drive.downloadedFileIds, isEmpty);
      expect(drive.uploadSnapshotCalled, isFalse);
    });

    test('returns noLegacyFiles when no snapshots and no legacy files exist',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: <Map<String, dynamic>>[],
        legacyFiles: <Map<String, dynamic>>[],
      );

      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
        driveService: drive,
      );

      final MigrationResult result = await migration.autoMigrate();

      expect(result.status, MigrationStatus.noLegacyFiles);
      expect(result.hasNoFiles, isTrue);
      expect(result.filesProcessed, 0);
      expect(repo.importCalls, 0);
      expect(drive.uploadSnapshotCalled, isFalse);
    });

    test('fails closed when duplicate monthly backup file names exist',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: <Map<String, dynamic>>[],
        legacyFiles: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'legacy-1',
            'name': 'expense-tracker-2026-10.json',
          },
          <String, dynamic>{
            'id': 'legacy-2',
            'name': 'expense-tracker-2026-10.json', // Duplicate name in Drive
          },
        ],
      );

      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
        driveService: drive,
      );

      expect(
        () => migration.autoMigrate(),
        throwsA(isA<MigrationException>().having(
          (MigrationException e) => e.message,
          'message',
          contains('Duplicate monthly backup file name detected'),
        )),
      );
      expect(repo.importCalls, 0);
      expect(drive.uploadSnapshotCalled, isFalse);
    });

    test('fails closed when duplicate months exist with different names',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
      );

      final String content1 = _monthlyJson(
        year: 2026,
        month: 10,
        transactions: <Map<String, dynamic>>[
          _row(date: '2026-10-01', amount: 100000.0),
        ],
      );
      final String content2 = _monthlyJson(
        year: 2026,
        month: 10,
        transactions: <Map<String, dynamic>>[
          _row(date: '2026-10-10', amount: 200000.0),
        ],
      );

      expect(
        () => migration.prepareFromFiles(<LegacyFileEntry>[
          LegacyFileEntry(name: 'file-a.json', content: content1),
          LegacyFileEntry(name: 'file-b.json', content: content2),
        ]),
        throwsA(isA<MigrationException>().having(
          (MigrationException e) => e.message,
          'message',
          contains('Duplicate monthly backups detected for month "2026-10"'),
        )),
      );
      expect(repo.importCalls, 0);
    });

    test('fails closed before DB write when any file is invalid JSON', () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: <Map<String, dynamic>>[],
        legacyFiles: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'f1',
            'name': 'expense-tracker-2026-09.json',
          },
          <String, dynamic>{
            'id': 'f2',
            'name': 'expense-tracker-2026-10.json',
          },
        ],
        fileContents: <String, String>{
          'f1': _monthlyJson(
            year: 2026,
            month: 9,
            transactions: <Map<String, dynamic>>[_row(date: '2026-09-10')],
          ),
          'f2': '{"unclosed-json": true',
        },
      );

      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
        driveService: drive,
      );

      expect(
        () => migration.autoMigrate(),
        throwsA(isA<MigrationException>().having(
          (MigrationException e) => e.message,
          'message',
          contains('not readable as valid JSON'),
        )),
      );

      // Verify no database writes were made for either file
      expect(repo.importCalls, 0);
      expect(repo.transactions, isEmpty);
      expect(drive.uploadSnapshotCalled, isFalse);
    });

    test(
        'fails closed before DB write when any file contains unreadable/invalid transaction',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: <Map<String, dynamic>>[],
        legacyFiles: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'f1',
            'name': 'expense-tracker-2026-09.json',
          },
          <String, dynamic>{
            'id': 'f2',
            'name': 'expense-tracker-2026-10.json',
          },
        ],
        fileContents: <String, String>{
          'f1': _monthlyJson(
            year: 2026,
            month: 9,
            transactions: <Map<String, dynamic>>[_row(date: '2026-09-10')],
          ),
          // f2 has an invalid transaction: negative amount
          'f2': _monthlyJson(
            year: 2026,
            month: 10,
            transactions: <Map<String, dynamic>>[
              _row(date: '2026-10-01', amount: -50000.0),
            ],
          ),
        },
      );

      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
        driveService: drive,
      );

      expect(
        () => migration.autoMigrate(),
        throwsA(isA<MigrationException>().having(
          (MigrationException e) => e.message,
          'message',
          contains('contains unreadable or invalid transaction'),
        )),
      );

      expect(repo.importCalls, 0);
      expect(repo.transactions, isEmpty);
      expect(drive.uploadSnapshotCalled, isFalse);
    });

    test('fails closed on unsafe unicode runes in category or note', () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
      );

      const String unsafeNote = 'Fake\u202Ereversed text';
      final String jsonText = _monthlyJson(
        year: 2026,
        month: 10,
        transactions: <Map<String, dynamic>>[
          _row(note: unsafeNote),
        ],
      );

      expect(
        () => migration.validateAndParseMonthlyJson(
          fileName: 'expense-tracker-2026-10.json',
          jsonText: jsonText,
        ),
        throwsA(isA<MigrationException>()),
      );
    });

    test('fails closed when filename and internal period disagree', () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
      );

      final String jsonText = _monthlyJson(
        year: 2026,
        month: 11, // specifies month 11
        transactions: <Map<String, dynamic>>[_row(date: '2026-11-05')],
      );

      expect(
        () => migration.validateAndParseMonthlyJson(
          fileName: 'expense-tracker-2026-10.json', // claims month 10
          jsonText: jsonText,
        ),
        throwsA(isA<MigrationException>().having(
          (MigrationException e) => e.message,
          'message',
          contains('name indicates 2026-10 but content specifies 2026-11'),
        )),
      );
    });
  });

  group('LegacyMigrationUseCase - Execution and Snapshot Integration', () {
    test(
        'successfully migrates multi-month backups atomically and produces snapshot without deleting files',
        () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: <Map<String, dynamic>>[],
        legacyFiles: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'f1',
            'name': 'expense-tracker-2026-08.json',
          },
          <String, dynamic>{
            'id': 'f2',
            'name': 'expense-tracker-2026-09.json',
          },
        ],
        fileContents: <String, String>{
          'f1': _monthlyJson(
            year: 2026,
            month: 8,
            transactions: <Map<String, dynamic>>[
              _row(
                date: '2026-08-10',
                type: 'income',
                category: 'Salary',
                amount: 10000000.0,
              ),
              _row(
                date: '2026-08-15',
                type: 'expense',
                category: 'Food',
                amount: 150000.0,
              ),
            ],
          ),
          'f2': _monthlyJson(
            year: 2026,
            month: 9,
            transactions: <Map<String, dynamic>>[
              _row(
                date: '2026-09-01',
                type: 'income',
                category: 'Salary',
                amount: 10000000.0,
              ),
              _row(
                date: '2026-09-12',
                type: 'expense',
                category: 'Transport',
                amount: 200000.0,
              ),
            ],
          ),
        },
      );

      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
        driveService: drive,
      );

      final DateTime snapshotFixedTime = DateTime(2026, 11, 6, 12, 0, 0);
      final MigrationResult result = await migration.autoMigrate(
        snapshotExportTime: snapshotFixedTime,
      );

      expect(result.status, MigrationStatus.completed);
      expect(result.isCompleted, isTrue);
      expect(result.filesProcessed, 2);
      expect(result.totalTransactions, 4);
      expect(result.importedCount, 4);
      expect(result.duplicatesCount, 0);

      // Verify single atomic import call to repository
      expect(repo.importCalls, 1);
      expect(repo.transactions.length, 4);

      // Verify snapshot was prepared
      expect(result.preparedSnapshot, isNotNull);
      final dynamic snapshotJson = result.preparedSnapshot!.json;
      expect(snapshotJson['backupType'], 'snapshot');
      expect(snapshotJson['summary']['totalIncome'], 20000000.0);
      expect(snapshotJson['summary']['totalExpense'], 350000.0);
      expect((snapshotJson['transactions'] as List<dynamic>).length, 4);

      // Verify NO files were deleted and uploadSnapshot (which prunes) was NOT called
      expect(drive.uploadSnapshotCalled, isFalse);
      expect(drive.deletedFileIds, isEmpty);
    });

    test('merges without overwriting existing local data', () async {
      final _MockTransactionRepository repo = _MockTransactionRepository();
      // Pre-populate 1 existing transaction in repo
      await repo.insertTransaction(TransactionEntity(
        id: 1,
        type: 'expense',
        amount: 150000.0,
        categoryId: 1,
        subcategoryId: null,
        categoryName: 'Food',
        subcategoryName: 'Groceries',
        note: 'Weekly market',
        date: DateTime(2026, 10, 15),
        createdAt: DateTime(2026, 10, 15),
      ));

      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: <Map<String, dynamic>>[],
        legacyFiles: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'f1',
            'name': 'expense-tracker-2026-10.json',
          },
        ],
        fileContents: <String, String>{
          'f1': _monthlyJson(
            year: 2026,
            month: 10,
            transactions: <Map<String, dynamic>>[
              _row(
                date: '2026-10-15',
                type: 'expense',
                category: 'Food',
                subcategory: 'Groceries',
                amount: 150000.0,
                note: 'Weekly market', // Duplicate of existing
              ),
              _row(
                date: '2026-10-20',
                type: 'expense',
                category: 'Utilities',
                amount: 500000.0, // New transaction
              ),
            ],
          ),
        },
      );

      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
        driveService: drive,
      );

      final MigrationResult result = await migration.autoMigrate();

      expect(result.status, MigrationStatus.completed);
      expect(result.filesProcessed, 1);
      expect(result.importedCount, 1);
      expect(result.duplicatesCount, 1);
      expect(result.totalTransactions, 2);

      // Verify total records in repo is 2 (1 existing + 1 new, duplicate not inserted twice)
      expect(repo.transactions.length, 2);
    });

    test('rolls back and propagates error if database import throws', () async {
      final _MockTransactionRepository repo = _MockTransactionRepository()
        ..throwOnImport = true;

      final _FakeSnapshotDriveService drive = _FakeSnapshotDriveService(
        snapshots: <Map<String, dynamic>>[],
        legacyFiles: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'f1',
            'name': 'expense-tracker-2026-10.json',
          },
        ],
        fileContents: <String, String>{
          'f1': _monthlyJson(
            year: 2026,
            month: 10,
            transactions: <Map<String, dynamic>>[_row()],
          ),
        },
      );

      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
        driveService: drive,
      );

      expect(
        () => migration.autoMigrate(),
        throwsA(isA<StateError>()),
      );
      expect(drive.uploadSnapshotCalled, isFalse);
    });
  });

  group('LegacyMigrationUseCase - Real In-Memory SQLite Integration', () {
    sqliteTest(
        'integrates with real drift repository, populating categories and generating snapshot',
        (AppDatabase db) async {
      final TransactionRepositoryImpl repo = TransactionRepositoryImpl(db);
      final LegacyMigrationUseCase migration = LegacyMigrationUseCase(
        repository: repo,
      );

      final Map<String, String> localFiles = <String, String>{
        'expense-tracker-2026-08.json': _monthlyJson(
          year: 2026,
          month: 8,
          transactions: <Map<String, dynamic>>[
            _row(
              date: '2026-08-01',
              type: 'income',
              category: 'Salary',
              amount: 5000000.0,
            ),
          ],
        ),
        'expense-tracker-2026-09.json': _monthlyJson(
          year: 2026,
          month: 9,
          transactions: <Map<String, dynamic>>[
            _row(
              date: '2026-09-05',
              type: 'expense',
              category: 'Health',
              subcategory: 'Pharmacy',
              amount: 75000.0,
            ),
          ],
        ),
      };

      final MigrationResult result =
          await migration.autoMigrate(localFiles: localFiles);

      expect(result.status, MigrationStatus.completed);
      expect(result.filesProcessed, 2);
      expect(result.importedCount, 2);
      expect(result.duplicatesCount, 0);

      // Verify DB rows exist
      final List<TransactionEntity> all = await repo.getAllTransactions();
      expect(all.length, 2);
      expect(all.any((TransactionEntity t) => t.categoryName == 'Salary'), isTrue);
      expect(all.any((TransactionEntity t) => t.categoryName == 'Health'), isTrue);
      expect(all.any((TransactionEntity t) => t.subcategoryName == 'Pharmacy'), isTrue);

      // Verify snapshot produced
      expect(result.preparedSnapshot, isNotNull);
      expect(result.preparedSnapshot!.transactionCount, 2);
      expect(result.preparedSnapshot!.totalIncome, 5000000.0);
      expect(result.preparedSnapshot!.totalExpense, 75000.0);
    });
  });
}

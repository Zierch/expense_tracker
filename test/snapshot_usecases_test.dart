import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/transaction_repository_impl.dart';
import 'package:expense_tracker/domain/usecases/export_snapshot_usecase.dart';
import 'package:expense_tracker/domain/usecases/import_snapshot_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sqlite_support.dart';

/// Helper to serialize a snapshot JSON document.
String _buildSnapshotJson({
  required List<Map<String, dynamic>> transactions,
  String app = 'Expense Tracker',
  num schemaVersion = 1,
  String? backupType = 'snapshot',
}) {
  return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
    'app': app,
    'schemaVersion': schemaVersion,
    if (backupType != null) 'backupType': backupType,
    'currency': 'IDR',
    'exportedAt': '2026-11-06T12:00:00',
    'period': <String, dynamic>{
      'type': 'all',
      'monthCount': 2,
      'startDate': '2026-01-01',
      'endDate': '2026-02-28',
    },
    'summary': <String, dynamic>{
      'totalIncome': 1000000.0,
      'totalExpense': 500000.0,
      'balance': 500000.0,
      'incomeByCategory': <Map<String, dynamic>>[],
      'expenseByCategory': <Map<String, dynamic>>[],
    },
    'transactions': transactions,
  });
}

Map<String, dynamic> _row({
  int id = 1,
  String date = '2026-01-15',
  String type = 'expense',
  String category = 'Expense',
  String? subcategory = 'Food',
  Object? amount = 250000.0,
  String? note,
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

Future<void> _insertTransaction(
  AppDatabase db, {
  required DateTime date,
  required String type,
  required double amount,
  required String category,
  String? subcategory,
  String? note,
}) async {
  final int categoryId = await db.findOrCreateCategory(category, type);
  final int? subcategoryId = subcategory == null
      ? null
      : await db.findOrCreateSubcategory(subcategory, categoryId);

  await db.insertTransaction(TransactionsCompanion.insert(
    type: type,
    amount: amount,
    categoryId: categoryId,
    subcategoryId: Value(subcategoryId),
    note: Value(note),
    date: date,
    createdAt: Value(date),
  ));
}

Future<int> _rowCount(AppDatabase db) async =>
    (await db.select(db.transactions).get()).length;

/// Real in-memory database that fails on row insertion to test atomic rollback.
class _FailingDatabase extends AppDatabase {
  _FailingDatabase(super.executor) : super.withExecutor();

  int inserts = 0;

  @override
  Future<int> insertTransaction(TransactionsCompanion transaction) {
    inserts++;
    if (inserts == 2) {
      throw StateError('the disk filled up');
    }
    return super.insertTransaction(transaction);
  }
}

void main() {
  group('ExportSnapshotUseCase', () {
    sqliteTest('empty database exports valid empty snapshot',
        (AppDatabase db) async {
      final ExportSnapshotUseCase export =
          ExportSnapshotUseCase(TransactionRepositoryImpl(db));
      final DateTime fixedTime = DateTime(2026, 11, 6, 12, 0, 0);

      final SnapshotExport result = await export(now: fixedTime);

      expect(result.fileName, 'expense-tracker-snapshot-20261106T120000.json');
      expect(result.transactionCount, 0);
      expect(result.totalIncome, 0.0);
      expect(result.totalExpense, 0.0);
      expect(result.monthsCount, 0);

      final Map<String, dynamic> json = result.json;
      expect(json['app'], 'Expense Tracker');
      expect(json['schemaVersion'], 1);
      expect(json['backupType'], 'snapshot');
      expect(json['currency'], 'IDR');
      expect(json['exportedAt'], '2026-11-06T12:00:00');
      expect(json['period']['type'], 'all');
      expect(json['period']['monthCount'], 0);
      expect(json['period']['startDate'], isNull);
      expect(json['period']['endDate'], isNull);
      expect(json['transactions'], isEmpty);
    });

    sqliteTest('exports all transactions across multiple months chronologically',
        (AppDatabase db) async {
      await _insertTransaction(
        db,
        date: DateTime(2026, 3, 10),
        type: 'expense',
        amount: 150000.0,
        category: 'Expense',
        subcategory: 'Food',
        note: 'March lunch',
      );
      await _insertTransaction(
        db,
        date: DateTime(2025, 12, 25),
        type: 'income',
        amount: 5000000.0,
        category: 'Income',
        subcategory: 'Bonus',
        note: 'Holiday bonus',
      );
      await _insertTransaction(
        db,
        date: DateTime(2026, 1, 5),
        type: 'expense',
        amount: 300000.0,
        category: 'Expense',
        subcategory: 'Bills',
        note: 'Internet',
      );

      final ExportSnapshotUseCase export =
          ExportSnapshotUseCase(TransactionRepositoryImpl(db));
      final DateTime fixedTime = DateTime(2026, 11, 6, 14, 30, 0);

      final SnapshotExport result = await export(now: fixedTime);

      expect(result.fileName, 'expense-tracker-snapshot-20261106T143000.json');
      expect(result.transactionCount, 3);
      expect(result.totalIncome, 5000000.0);
      expect(result.totalExpense, 450000.0);
      expect(result.monthsCount, 3);

      final Map<String, dynamic> json = result.json;
      expect(json['period']['startDate'], '2025-12-25');
      expect(json['period']['endDate'], '2026-03-10');
      expect(json['period']['monthCount'], 3);

      final List<dynamic> transactions = json['transactions'] as List<dynamic>;
      expect(transactions.length, 3);
      // Verify chronological order: 2025-12-25, 2026-01-05, 2026-03-10
      expect(transactions[0]['date'], '2025-12-25');
      expect(transactions[0]['type'], 'income');
      expect(transactions[0]['amount'], 5000000.0);
      expect(transactions[1]['date'], '2026-01-05');
      expect(transactions[1]['type'], 'expense');
      expect(transactions[2]['date'], '2026-03-10');
      expect(transactions[2]['type'], 'expense');
    });
  });

  group('ImportSnapshotUseCase', () {
    sqliteTest('imports multi-month snapshot and creates missing categories',
        (AppDatabase db) async {
      final ImportSnapshotUseCase importer =
          ImportSnapshotUseCase(TransactionRepositoryImpl(db));

      final String snapshot = _buildSnapshotJson(
        transactions: <Map<String, dynamic>>[
          _row(
            date: '2025-11-20',
            type: 'income',
            amount: 6000000.0,
            category: 'Income',
            subcategory: 'Consulting',
            note: 'Nov contract',
          ),
          _row(
            date: '2026-01-10',
            type: 'expense',
            amount: 75000.0,
            category: 'Expense',
            subcategory: 'CustomSubcat',
            note: 'Coffee',
          ),
          _row(
            date: '2026-02-14',
            type: 'expense',
            amount: 500000.0,
            category: 'CustomCategory',
            subcategory: 'Dinner',
            note: 'Valentine',
          ),
        ],
      );

      final SnapshotImportResult result = await importer(snapshot);

      expect(result.imported, 3);
      expect(result.duplicates, 0);
      expect(result.unreadable, 0);
      expect(result.monthsCount, 3);
      expect(result.backupType, 'snapshot');
      expect(await _rowCount(db), 3);

      final int expenseCatId =
          (await db.getCategories(type: 'expense')).first.id;
      final List<String> subcategories =
          (await db.getSubcategories(expenseCatId))
              .map((Subcategory s) => s.name)
              .toList();
      expect(subcategories, contains('CustomSubcat'));

      final List<Category> customCats =
          (await db.getCategories(type: 'expense'))
              .where((Category c) => c.name == 'CustomCategory')
              .toList();
      expect(customCats, hasLength(1));
    });

    sqliteTest('repeat import is idempotent and does not duplicate rows',
        (AppDatabase db) async {
      final ImportSnapshotUseCase importer =
          ImportSnapshotUseCase(TransactionRepositoryImpl(db));

      final String snapshot = _buildSnapshotJson(
        transactions: <Map<String, dynamic>>[
          _row(date: '2026-01-15', amount: 200000.0, note: 'Grocery'),
          _row(date: '2026-02-20', amount: 350000.0, note: 'Utilities'),
        ],
      );

      final SnapshotImportResult first = await importer(snapshot);
      expect(first.imported, 2);
      expect(first.duplicates, 0);
      expect(await _rowCount(db), 2);

      final SnapshotImportResult second = await importer(snapshot);
      expect(second.imported, 0);
      expect(second.duplicates, 2);
      expect(second.unreadable, 0);
      expect(await _rowCount(db), 2);
    });

    sqliteTest('merges non-destructively without overwriting local transactions',
        (AppDatabase db) async {
      await _insertTransaction(
        db,
        date: DateTime(2026, 1, 10),
        type: 'expense',
        amount: 100000.0,
        category: 'Expense',
        subcategory: 'Food',
        note: 'Existing local',
      );

      final ImportSnapshotUseCase importer =
          ImportSnapshotUseCase(TransactionRepositoryImpl(db));

      final String snapshot = _buildSnapshotJson(
        transactions: <Map<String, dynamic>>[
          _row(
            date: '2026-01-10',
            amount: 100000.0,
            category: 'Expense',
            subcategory: 'Food',
            note: 'Existing local',
          ),
          _row(
            date: '2026-02-05',
            amount: 250000.0,
            category: 'Expense',
            subcategory: 'Food',
            note: 'New row from snapshot',
          ),
        ],
      );

      final SnapshotImportResult result = await importer(snapshot);
      expect(result.imported, 1);
      expect(result.duplicates, 1);
      expect(await _rowCount(db), 2);

      final List<Transaction> allRows =
          await db.select(db.transactions).get();
      expect(
        allRows.map((Transaction t) => t.note),
        containsAll(<String>['Existing local', 'New row from snapshot']),
      );
    });

    test('atomic rollback on database failure leaves local database untouched',
        () async {
      final AppDatabase? db =
          openInMemoryOrSkip(() => _FailingDatabase(NativeDatabase.memory()));
      if (db == null) return;

      try {
        final ImportSnapshotUseCase importer =
            ImportSnapshotUseCase(TransactionRepositoryImpl(db));

        final String snapshot = _buildSnapshotJson(
          transactions: <Map<String, dynamic>>[
            _row(
              date: '2026-01-01',
              subcategory: 'FirstSubcat',
              note: 'First insert succeeds',
            ),
            _row(
              date: '2026-02-01',
              subcategory: 'SecondSubcat',
              note: 'Second insert throws',
            ),
          ],
        );

        await expectLater(
          importer(snapshot),
          throwsA(isA<StateError>()),
        );

        // Entire transaction rolled back: 0 rows inserted
        expect(await _rowCount(db), 0);

        // Created subcategory also rolled back
        final int expenseId =
            (await db.getCategories(type: 'expense')).first.id;
        final List<String> subcategories =
            (await db.getSubcategories(expenseId))
                .map((Subcategory s) => s.name)
                .toList();
        expect(subcategories, isNot(contains('FirstSubcat')));
        expect(subcategories, isNot(contains('SecondSubcat')));
      } finally {
        await db.close();
      }
    });

    sqliteTest('counts unreadable rows and imports valid neighbors',
        (AppDatabase db) async {
      final ImportSnapshotUseCase importer =
          ImportSnapshotUseCase(TransactionRepositoryImpl(db));

      final String snapshot = _buildSnapshotJson(
        transactions: <Map<String, dynamic>>[
          _row(date: '2026-01-05', amount: 150000.0, note: 'Valid row 1'),
          _row(amount: 'not a number'),
          _row(amount: -1000.0),
          _row(amount: 0),
          _row(amount: 2e12), // above _maxAmount
          _row(date: 'invalid-date-string'),
          _row(type: 'transfer'), // invalid type
          _row(category: ''), // empty category
          _row(category: 'ValidCat\u202EBadRune'), // unsafe rune (RTL override)
          _row(date: '2026-02-10', amount: 300000.0, note: 'Valid row 2'),
        ],
      );

      final SnapshotImportResult result = await importer(snapshot);

      expect(result.imported, 2);
      expect(result.unreadable, 8);
      expect(result.duplicates, 0);
      expect(result.total, 10);
      expect(await _rowCount(db), 2);
    });

    sqliteTest('refuses invalid JSON, bad app, and unsupported schema versions',
        (AppDatabase db) async {
      final ImportSnapshotUseCase importer =
          ImportSnapshotUseCase(TransactionRepositoryImpl(db));

      await expectLater(
        importer('{ invalid json'),
        throwsA(
          isA<SnapshotImportException>().having(
            (SnapshotImportException e) => e.message,
            'message',
            contains('not readable as JSON'),
          ),
        ),
      );

      await expectLater(
        importer('["not an object"]'),
        throwsA(
          isA<SnapshotImportException>().having(
            (SnapshotImportException e) => e.message,
            'message',
            contains('not an Expense Tracker backup'),
          ),
        ),
      );

      final String wrongApp = _buildSnapshotJson(
        app: 'DifferentApp',
        transactions: <Map<String, dynamic>>[_row()],
      );
      await expectLater(
        importer(wrongApp),
        throwsA(
          isA<SnapshotImportException>().having(
            (SnapshotImportException e) => e.message,
            'message',
            contains('DifferentApp'),
          ),
        ),
      );

      final String newerSchema = _buildSnapshotJson(
        schemaVersion: 2,
        transactions: <Map<String, dynamic>>[_row()],
      );
      await expectLater(
        importer(newerSchema),
        throwsA(
          isA<SnapshotImportException>().having(
            (SnapshotImportException e) => e.message,
            'message',
            contains('newer version of the app'),
          ),
        ),
      );

      const String noTransactions = '{"app":"Expense Tracker","schemaVersion":1}';
      await expectLater(
        importer(noTransactions),
        throwsA(
          isA<SnapshotImportException>().having(
            (SnapshotImportException e) => e.message,
            'message',
            contains('no transactions in it'),
          ),
        ),
      );
    });

    sqliteTest('supports legacy monthly backup JSON format seamlessly',
        (AppDatabase db) async {
      final ImportSnapshotUseCase importer =
          ImportSnapshotUseCase(TransactionRepositoryImpl(db));

      final String legacyMonthly = const JsonEncoder.withIndent('  ').convert(
        <String, dynamic>{
          'app': 'Expense Tracker',
          'schemaVersion': 1,
          'currency': 'IDR',
          'exportedAt': '2026-10-31T20:00:00',
          'period': <String, dynamic>{
            'year': 2026,
            'month': 10,
            'startDate': '2026-10-01',
            'endDate': '2026-10-31',
          },
          'summary': <String, dynamic>{
            'totalIncome': 0.0,
            'totalExpense': 250000.0,
            'balance': -250000.0,
            'incomeByCategory': <Map<String, dynamic>>[],
            'expenseByCategory': <Map<String, dynamic>>[],
          },
          'transactions': <Map<String, dynamic>>[
            _row(
              date: '2026-10-15',
              amount: 250000.0,
              note: 'Legacy monthly row',
            ),
          ],
        },
      );

      final SnapshotImportResult result = await importer(legacyMonthly);

      expect(result.imported, 1);
      expect(result.duplicates, 0);
      expect(result.unreadable, 0);
      expect(result.monthsCount, 1);
      expect(result.backupType, 'monthly');
      expect(await _rowCount(db), 1);
    });

    sqliteTest('round-trip export and import between separate databases',
        (AppDatabase sourceDb) async {
      await _insertTransaction(
        sourceDb,
        date: DateTime(2025, 6, 12),
        type: 'expense',
        amount: 85000.0,
        category: 'Expense',
        subcategory: 'Food',
        note: 'Mid-year meal',
      );
      await _insertTransaction(
        sourceDb,
        date: DateTime(2026, 3, 20),
        type: 'income',
        amount: 12000000.0,
        category: 'Income',
        subcategory: 'Salary',
        note: 'Spring salary',
      );

      final ExportSnapshotUseCase export =
          ExportSnapshotUseCase(TransactionRepositoryImpl(sourceDb));
      final SnapshotExport exportData = await export();

      final AppDatabase? destDb = openInMemoryOrSkip(
          () => AppDatabase.withExecutor(NativeDatabase.memory()));
      if (destDb == null) return;

      try {
        final ImportSnapshotUseCase importer =
            ImportSnapshotUseCase(TransactionRepositoryImpl(destDb));
        final SnapshotImportResult importResult =
            await importer(exportData.jsonText);

        expect(importResult.imported, 2);
        expect(importResult.duplicates, 0);
        expect(importResult.unreadable, 0);
        expect(importResult.monthsCount, 2);

        final List<Transaction> destRows =
            await destDb.select(destDb.transactions).get();
        expect(destRows, hasLength(2));
        expect(
          await destDb.getTotalIncome(),
          await sourceDb.getTotalIncome(),
        );
        expect(
          await destDb.getTotalExpense(),
          await sourceDb.getTotalExpense(),
        );
      } finally {
        await destDb.close();
      }
    });
  });
}

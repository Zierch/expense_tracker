// The edit page has to hand over the creation time the row already has.
//
// A stored creation time survives an edit at the storage level — that half is pinned in
// `transaction_created_at_test.dart` — and the repository does not send `createdAt` at
// all, so a wrong value in the entity below is invisible in the database, and no screen
// shows the column either. That is precisely why it needs asserting here: nothing else
// would notice the day it becomes visible, and the page is the only place that decides it.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/transaction_repository_impl.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/presentation/pages/add_transaction_page.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'sqlite_support.dart';

/// A repository that keeps whatever the page asks it to update, then does it for real.
class _Recorder implements TransactionRepository {
  _Recorder(this._inner);

  final TransactionRepository _inner;

  TransactionEntity? updated;

  @override
  Future<bool> updateTransaction(TransactionEntity transaction) {
    updated = transaction;
    return _inner.updateTransaction(transaction);
  }

  @override
  Future<int> insertTransaction(TransactionEntity transaction) =>
      _inner.insertTransaction(transaction);

  @override
  Future<List<TransactionEntity>> getAllTransactions() => _inner.getAllTransactions();

  @override
  Stream<List<TransactionEntity>> watchAllTransactions() => _inner.watchAllTransactions();

  @override
  Future<List<TransactionEntity>> getTransactionsByDateRange(DateTime start, DateTime end) =>
      _inner.getTransactionsByDateRange(start, end);

  @override
  Future<int> deleteTransaction(int id) => _inner.deleteTransaction(id);

  @override
  Future<double> getTotalIncome({DateTime? start, DateTime? end}) =>
      _inner.getTotalIncome(start: start, end: end);

  @override
  Future<double> getTotalExpense({DateTime? start, DateTime? end}) =>
      _inner.getTotalExpense(start: start, end: end);

  @override
  Future<Map<String, double>> getExpenseByCategory({DateTime? start, DateTime? end}) =>
      _inner.getExpenseByCategory(start: start, end: end);

  @override
  Future<Map<String, double>> getIncomeByCategory({DateTime? start, DateTime? end}) =>
      _inner.getIncomeByCategory(start: start, end: end);
}

/// The same, except that the rows the page loads its transaction from never arrive.
class _StalledRepository extends _Recorder {
  _StalledRepository(super.inner);

  @override
  Future<List<TransactionEntity>> getAllTransactions() =>
      Completer<List<TransactionEntity>>().future;
}

void main() {
  /// A window tall enough for the whole form to be built.
  ///
  /// A `ListView` only builds what is visible, so on the default test surface the button
  /// at the bottom of this form does not exist and cannot be tapped or inspected.
  void useTallWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Pumps the edit page for [transactionId] with [repository] behind it.
  Future<void> pumpEditPage(
    WidgetTester tester,
    AppDatabase db,
    int transactionId,
    TransactionRepository repository,
  ) async {
    final GoRouter router = GoRouter(
      initialLocation: '/edit',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
        GoRoute(
          path: '/edit',
          builder: (_, __) => AddTransactionPage(transactionId: transactionId),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        transactionRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
  }

  sqliteWidgetTest(
    'editing a transaction keeps the creation time',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);

      // Fixed, and years away from the clock the test runs on, so a value taken from
      // `DateTime.now()` cannot be mistaken for the stored one.
      final DateTime recorded = DateTime(2020, 1, 1, 9, 30);
      final int categoryId = (await db.getCategories(type: 'expense')).first.id;
      final int id = await db.insertTransaction(TransactionsCompanion.insert(
        type: 'expense',
        amount: 10000,
        categoryId: categoryId,
        date: DateTime(2026, 10, 15),
        createdAt: Value(recorded),
      ));

      final _Recorder repository = _Recorder(TransactionRepositoryImpl(db));

      await pumpEditPage(tester, db, id, repository);
      await tester.pumpAndSettle();

      expect(find.text('Edit Transaction'), findsOneWidget,
          reason: 'the page has to be in edit mode, or the assertion below would be '
              'about the add path');
      // The loaded amount, so that a tap cannot land on a form that is still empty: that
      // would fail later as "the button did nothing", which reads like a different problem.
      expect(find.text('10000'), findsOneWidget);
      expect(repository.updated, isNull);

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(repository.updated, isNotNull,
          reason: 'the button has to reach the repository, or the rest of this test '
              'passes for the wrong reason');
      expect(repository.updated!.id, id);
      expect(repository.updated!.createdAt, recorded,
          reason: 'the page must pass on the stored creation time, not the time of '
              'the edit');

      final Transaction row =
          await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
      expect(row.amount, 10000,
          reason: 'the recorded update must have reached the database, and nothing '
              'else about the row should have moved');
    },
  );

  sqliteWidgetTest(
    'an edit cannot be saved before its row has arrived',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);

      final _StalledRepository repository = _StalledRepository(TransactionRepositoryImpl(db));

      await pumpEditPage(tester, db, 1, repository);
      await tester.pumpAndSettle();

      // Without the row there is nothing truthful to write: the category on screen is the
      // first one the categories query returned, not the transaction's.
      expect(find.text('Update'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull,
          reason: 'an edit whose row has not arrived must not offer to save');

      await tester.tap(find.text('Update'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(repository.updated, isNull);
    },
  );
}

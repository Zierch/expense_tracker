// The dashboard has to re-run its queries when the user pulls it down.
//
// The screen reads one snapshot of the month through two providers — a live stream for
// the rows and a one-shot future for the totals — so a refresh is only observable by
// watching the repository itself: the data would look identical either way, and a pull
// that quietly did nothing would still leave a correct-looking list on screen. Counting
// the calls is what binds the gesture to the work.
//
// The empty case is asserted separately because it is the one a naive `RefreshIndicator`
// breaks: a short, non-scrollable child never reports the overscroll the indicator arms
// on, so the pull would silently stop working exactly when the list is empty.

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/transaction_repository_impl.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/presentation/pages/home_page.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sqlite_support.dart';

/// A repository that counts the reads a refresh is supposed to re-issue, then does them.
class _CountingRepository implements TransactionRepository {
  _CountingRepository(this._inner);

  final TransactionRepository _inner;

  /// How many times the rows were (re-)subscribed to.
  int watchCalls = 0;

  /// How many times the month's income was (re-)asked for; the summary is the other half
  /// of the screen, and it is not derived from the row stream.
  int totalIncomeCalls = 0;

  @override
  Stream<List<TransactionEntity>> watchAllTransactions() {
    watchCalls++;
    return _inner.watchAllTransactions();
  }

  @override
  Future<double> getTotalIncome({DateTime? start, DateTime? end}) {
    totalIncomeCalls++;
    return _inner.getTotalIncome(start: start, end: end);
  }

  @override
  Future<int> insertTransaction(TransactionEntity transaction) =>
      _inner.insertTransaction(transaction);

  @override
  Future<List<TransactionEntity>> getAllTransactions() => _inner.getAllTransactions();

  @override
  Future<List<TransactionEntity>> getTransactionsByDateRange(DateTime start, DateTime end) =>
      _inner.getTransactionsByDateRange(start, end);

  @override
  Future<bool> updateTransaction(TransactionEntity transaction) =>
      _inner.updateTransaction(transaction);

  @override
  Future<int> deleteTransaction(int id) => _inner.deleteTransaction(id);

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

/// Pumps the dashboard with [repository] behind it.
///
/// No router is needed: `HomePage` only reaches for one from tap handlers, and this test
/// never taps a row.
Future<void> _pumpHome(
  WidgetTester tester,
  AppDatabase db,
  TransactionRepository repository,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      transactionRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(home: HomePage()),
  ));
}

/// Drags the dashboard down far enough to arm the refresh indicator.
Future<void> _pullToRefresh(WidgetTester tester) async {
  await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
  await tester.pumpAndSettle();
}

void main() {
  sqliteWidgetTest(
    'pulling the dashboard re-runs the queries behind it',
    (AppDatabase db, WidgetTester tester) async {
      // The month on screen is whatever "now" is, so the row has to be dated today or
      // the list would be empty and the pull would be tested against the other branch.
      final int categoryId = (await db.getCategories(type: 'expense')).first.id;
      await db.insertTransaction(TransactionsCompanion.insert(
        type: 'expense',
        amount: 10000,
        categoryId: categoryId,
        date: DateTime.now(),
        createdAt: Value(DateTime.now()),
      ));

      final _CountingRepository repository =
          _CountingRepository(TransactionRepositoryImpl(db));

      await _pumpHome(tester, db, repository);
      await tester.pumpAndSettle();

      final int watchesBefore = repository.watchCalls;
      final int totalsBefore = repository.totalIncomeCalls;
      expect(watchesBefore, greaterThan(0),
          reason: 'the pull below is only meaningful if the screen read something first');

      await _pullToRefresh(tester);

      expect(repository.watchCalls, greaterThan(watchesBefore),
          reason: 'the pulled stream has to be dropped and subscribed to again');
      expect(repository.totalIncomeCalls, greaterThan(totalsBefore),
          reason: 'the totals are a separate query and have to be re-run too, or the '
              'card would keep a stale month next to fresh rows');
    },
  );

  sqliteWidgetTest(
    'pulling works on the empty state as well',
    (AppDatabase db, WidgetTester tester) async {
      final _CountingRepository repository =
          _CountingRepository(TransactionRepositoryImpl(db));

      await _pumpHome(tester, db, repository);
      await tester.pumpAndSettle();

      expect(find.text('No transactions yet'), findsOneWidget,
          reason: 'this test is about the empty branch; without the assertion it would '
              'pass against the list branch and prove nothing');

      final int watchesBefore = repository.watchCalls;
      await _pullToRefresh(tester);

      expect(repository.watchCalls, greaterThan(watchesBefore),
          reason: 'a short, non-scrollable child makes `RefreshIndicator` silently inert, '
              'so the empty state must still report overscroll');
    },
  );

  sqliteWidgetTest(
    'a refresh survives the page being unmounted mid-flight',
    (AppDatabase db, WidgetTester tester) async {
      final _CountingRepository repository =
          _CountingRepository(TransactionRepositoryImpl(db));

      await _pumpHome(tester, db, repository);
      await tester.pumpAndSettle();

      // Start the pull but do not wait for it to finish
      await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
      await tester.pump();

      expect(find.byType(RefreshProgressIndicator), findsOneWidget,
          reason: 'the pull has to actually arm the refresh, or unmounting the page '
              'below proves nothing');

      // Replace the tree before the refresh completes, so the providers are disposed
      // while _refresh() is still awaiting them
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('gone'))));
      await tester.pumpAndSettle();

      // The point is that a disposed provider must not crash the app; _refresh()
      // catches and logs it
      expect(tester.takeException(), isNull,
          reason: 'a provider disposed mid-refresh must not throw to the framework, '
              'or the gesture would blow up the app');
    },
  );
}

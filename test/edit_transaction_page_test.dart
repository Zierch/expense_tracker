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
import 'package:expense_tracker/domain/entities/import_transaction.dart';
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
  Future<List<TransactionEntity>> getAllTransactions() =>
      _inner.getAllTransactions();

  @override
  Stream<List<TransactionEntity>> watchAllTransactions() =>
      _inner.watchAllTransactions();

  @override
  Future<List<TransactionEntity>> getTransactionsByDateRange(
          DateTime start, DateTime end) =>
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
  Future<Map<String, double>> getExpenseByCategory(
          {DateTime? start, DateTime? end}) =>
      _inner.getExpenseByCategory(start: start, end: end);

  @override
  Future<Map<String, double>> getIncomeByCategory(
          {DateTime? start, DateTime? end}) =>
      _inner.getIncomeByCategory(start: start, end: end);
  @override
  Future<List<DateTime>> getMonthsWithTransactions() =>
      _inner.getMonthsWithTransactions();

  @override
  Future<ImportWriteResult> importTransactions(
          List<ImportTransaction> transactions) =>
      _inner.importTransactions(transactions);
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
        GoRoute(
            path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
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
          reason:
              'the page has to be in edit mode, or the assertion below would be '
              'about the add path');
      // The loaded amount, so that a tap cannot land on a form that is still empty: that
      // would fail later as "the button did nothing", which reads like a different problem.
      // Shown the way the field groups it — the transfer from a stored number to the
      // screen is what this line is watching.
      expect(find.text('10.000'), findsOneWidget);
      expect(repository.updated, isNull);

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(repository.updated, isNotNull,
          reason:
              'the button has to reach the repository, or the rest of this test '
              'passes for the wrong reason');
      expect(repository.updated!.id, id);
      expect(repository.updated!.createdAt, recorded,
          reason:
              'the page must pass on the stored creation time, not the time of '
              'the edit');

      final Transaction row = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.amount, 10000,
          reason:
              'the recorded update must have reached the database, and nothing '
              'else about the row should have moved');
    },
  );

  sqliteWidgetTest(
    'an edit cannot be saved before its row has arrived',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);

      final _StalledRepository repository =
          _StalledRepository(TransactionRepositoryImpl(db));

      await pumpEditPage(tester, db, 1, repository);
      await tester.pumpAndSettle();

      // Without the row there is nothing truthful to write: the category on screen is the
      // first one the categories query returned, not the transaction's.
      expect(find.text('Update'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
          reason: 'an edit whose row has not arrived must not offer to save');

      await tester.tap(find.text('Update'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(repository.updated, isNull);
    },
  );

  /// A saved expense that already has a subcategory, and a second one to switch to.
  ///
  /// Both tests below start here, because the bug was about what the form does with a
  /// subcategory that is already stored: a fixture without one could not see it.
  /// `current` is the seeded `Food`, `other` a new `Taxi`.
  Future<({int transaction, int current, int other})> seedSubcategories(
    AppDatabase db, {
    String type = 'expense',
  }) async {
    final int categoryId = (await db.getCategories(type: type)).first.id;
    // Seeded on the `current` side, made here on the `other` side: the two types keep
    // their subcategories apart, so the names say which list a value came from.
    final String currentName = type == 'income' ? 'Salary' : 'Food';
    final String otherName = type == 'income' ? 'Refund' : 'Taxi';
    final int current = (await db.getSubcategories(categoryId))
        .firstWhere((Subcategory s) => s.name == currentName)
        .id;
    final int other = await db.into(db.subcategories).insert(
          SubcategoriesCompanion.insert(categoryId: categoryId, name: otherName),
        );

    final int transaction = await db.insertTransaction(
      TransactionsCompanion.insert(
        type: type,
        amount: 15000,
        categoryId: categoryId,
        subcategoryId: Value(current),
        date: DateTime(2026, 10, 20),
      ),
    );

    return (transaction: transaction, current: current, other: other);
  }

  /// The subcategory column of [transactionId], as the database now holds it.
  Future<int?> storedSubcategory(AppDatabase db, int transactionId) async {
    final Transaction row = await (db.select(db.transactions)
          ..where((t) => t.id.equals(transactionId)))
        .getSingle();
    return row.subcategoryId;
  }

  // The form used to open on "None" and then write that back. The subcategory was
  // cleared while the categories loaded, so an Update nobody meant as a change lost a
  // value the row already had — the worse half of the bug, because nothing on screen
  // said so once the dropdown had fallen back to None.
  sqliteWidgetTest('an edit opens on the stored subcategory and saves it again',
      (AppDatabase db, WidgetTester tester) async {
    useTallWindow(tester);
    final ({int transaction, int current, int other}) row =
        await seedSubcategories(db);

    await pumpEditPage(
        tester, db, row.transaction, _Recorder(TransactionRepositoryImpl(db)));
    await tester.pumpAndSettle();

    expect(find.text('Food'), findsOneWidget,
        reason: 'the form has to open on the subcategory the row already has');

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(await storedSubcategory(db, row.transaction), row.current,
        reason: 'saving without touching the dropdown must not clear it');

    // Unmounted before the database closes: a live page outlives the harness.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // The other branch of the same load. The page starts on the expense type and only
  // learns the row's type from the row, so an income edit is the case where the two
  // loads disagree — which is how a form could list one type's subcategories while
  // holding the other type's selection.
  sqliteWidgetTest('an edit of an income transaction opens on its own subcategory',
      (AppDatabase db, WidgetTester tester) async {
    useTallWindow(tester);
    final ({int transaction, int current, int other}) row =
        await seedSubcategories(db, type: 'income');

    await pumpEditPage(
        tester, db, row.transaction, _Recorder(TransactionRepositoryImpl(db)));
    await tester.pumpAndSettle();

    expect(find.text('Salary'), findsOneWidget,
        reason: "the row's own type decides which subcategories the form shows");
    expect(find.text('Food'), findsNothing,
        reason: 'an expense subcategory does not belong on an income row');

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(await storedSubcategory(db, row.transaction), row.current,
        reason: 'an income row keeps its own subcategory through a save');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  sqliteWidgetTest('an edit stores the subcategory the user picks',
      (AppDatabase db, WidgetTester tester) async {
    useTallWindow(tester);
    final ({int transaction, int current, int other}) row =
        await seedSubcategories(db);

    await pumpEditPage(
        tester, db, row.transaction, _Recorder(TransactionRepositoryImpl(db)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taxi').last);
    await tester.pumpAndSettle();

    // The field itself has to show the pick, not only the database: a form that
    // saves a value it does not display is the same bug wearing a different hat.
    expect(find.text('Taxi'), findsOneWidget);

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(await storedSubcategory(db, row.transaction), row.other,
        reason: 'the picked subcategory is what the Update has to store');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

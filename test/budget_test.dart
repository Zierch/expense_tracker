// Budgets: a monthly ceiling per category, shown as a bar on the statistics tab.
//
// Four things are pinned here, each one a way the feature could be wrong
// without looking wrong:
//
//  * Setting a ceiling twice has to leave *one* row. Two rows for the same
//    category would draw two bars in the list, or one bar reading a stale
//    amount, depending on which one the query returned first.
//  * An install that predates the feature has to upgrade in place. The
//    migration only adds a table, but "only" is exactly the kind of claim that
//    is cheap to check and expensive to be wrong about: a botched upgrade is
//    the user's transactions, gone.
//  * The provider the screen watches has to read the table the dialog writes.
//    The two halves are asserted apart — storage below, drawing after that —
//    so this is the one test that fails if they are ever wired to different
//    things.
//  * The row has to draw the ceiling it was given, in the right colour, and
//    the dialog has to leave the database changed. The screen takes its
//    ceilings from a stream, which a widget test owns: the app's stream comes
//    from drift and does not deliver under a test clock, so the test supplies
//    the stream and says what it carries.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/domain/entities/category_budget.dart';
import 'package:expense_tracker/presentation/pages/statistics_page.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'sqlite_support.dart';

/// The same formatting the screen uses, so the expectations cannot pass on a
/// string the screen would never print.
String _rp(double amount) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);

/// One expense on [date], filed under the seeded `Food` subcategory, so the
/// breakdown names it the way the statistics screen does.
Future<int> _insertFood(AppDatabase db, {required double amount, required DateTime date}) async {
  final int categoryId = (await db.getCategories(type: 'expense')).first.id;
  final Subcategory food = (await db.getSubcategories(categoryId))
      .firstWhere((Subcategory s) => s.name == 'Food');
  return db.insertTransaction(TransactionsCompanion.insert(
    type: 'expense',
    amount: amount,
    categoryId: categoryId,
    subcategoryId: Value(food.id),
    date: date,
    createdAt: Value(date),
  ));
}

/// What the table holds right now.
///
/// A one-shot query, not `watchBudgets().first`: a widget test runs on a fake
/// clock, and a stream's first event is delivered on a timer that only fires
/// while frames are pumped — awaiting it from the test body waits forever.
Future<List<CategoryBudget>> _storedBudgets(AppDatabase db) async {
  final List<Budget> rows = await db.select(db.budgets).get();
  return rows
      .map((Budget row) => CategoryBudget(name: row.name, type: row.type, amount: row.amount))
      .toList();
}

/// The statistics page with a real database behind it, on a phone-sized surface.
///
/// The default 800x600 test window puts the category card below the fold — the
/// weekly and daily sections sit above it — so a tap on its rows would miss
/// silently, and the dialog would be off-screen.
Future<void> _pumpStatistics(
  WidgetTester tester,
  AppDatabase db, {
  required Stream<List<CategoryBudget>> budgets,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      budgetsProvider.overrideWith((Ref ref) => budgets),
    ],
    child: const MaterialApp(home: StatisticsPage()),
  ));
  await _settle(tester);
}

/// A fixed number of frames, which is all these screens need to draw.
///
/// Not `pumpAndSettle`: a field with focus blinks its cursor and the page holds
/// live streams, so it never reports itself settled.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Takes the screen down before the test ends.
///
/// Closing the database while a screen still listens to it is something the app
/// never does, and it deadlocks the harness: `AppDatabase.close()` waits for
/// those streams, and they are only dropped when the providers go with the tree.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
}

void main() {
  sqliteTest('a ceiling set twice replaces the first, it does not stack', (AppDatabase db) async {
    await db.setBudget(name: 'Food', type: 'expense', amount: 1000000);
    await db.setBudget(name: 'Food', type: 'expense', amount: 1500000);

    final List<CategoryBudget> budgets = await _storedBudgets(db);
    expect(budgets, hasLength(1));
    expect(budgets.single.amount, 1500000);
  });

  sqliteTest('income and expense ceilings are separate rows', (AppDatabase db) async {
    await db.setBudget(name: 'Gift', type: 'expense', amount: 50000);
    await db.setBudget(name: 'Gift', type: 'income', amount: 200000);

    expect(await _storedBudgets(db), hasLength(2));
  });

  sqliteTest('a ceiling can be dropped, and dropping one leaves the others',
      (AppDatabase db) async {
    await db.setBudget(name: 'Food', type: 'expense', amount: 1000000);
    await db.setBudget(name: 'Rent', type: 'expense', amount: 3000000);

    await db.clearBudget(name: 'Food', type: 'expense');

    final List<CategoryBudget> budgets = await _storedBudgets(db);
    expect(budgets.map((CategoryBudget b) => b.name), <String>['Rent']);
  });

  sqliteTest('the stream the screen watches reads the table the dialog writes',
      (AppDatabase db) async {
    final ProviderContainer container =
        ProviderContainer(overrides: <Override>[databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);

    expect(await container.read(budgetsProvider.future), isEmpty);

    await db.setBudget(name: 'Food', type: 'expense', amount: 1000000);
    container.invalidate(budgetsProvider);
    final List<CategoryBudget> afterWrite = await container.read(budgetsProvider.future);

    expect(afterWrite.single.name, 'Food');
    expect(afterWrite.single.amount, 1000000);
  });

  test('a v2 install keeps its transactions and gains the new tables', () async {
    final Directory dir = Directory.systemTemp.createTempSync('expense_tracker_budget');
    final String path = p.join(dir.path, 'app.sqlite');

    // A database that looks like the one a user who installed before budgets
    // has: today's tables minus the ones the upgrades add, and a recorded
    // version of 2. Drift only runs `onUpgrade` when that number is behind the
    // schema, so this is what an upgrade actually looks at — and the tables the
    // upgrades are meant to create have to be missing for that to mean anything.
    final AppDatabase? before = openSqliteFileOrSkip(path);
    if (before == null) return;

    final DateTime date = DateTime(2026, 3, 4);
    final int rowId = await _insertFood(before, amount: 250000, date: date);
    await before.customStatement('DROP TABLE budgets');
    await before.customStatement('DROP TABLE recurring_templates');
    await before.customStatement('PRAGMA user_version = 2');
    await before.close();

    final AppDatabase? after = openSqliteFileOrSkip(path);
    if (after == null) return;
    try {
      final List<Transaction> rows = await after.getAllTransactions();
      expect(rows.map((Transaction t) => t.id), <int>[rowId]);
      expect(rows.single.amount, 250000);

      // And the tables the upgrades were supposed to add are usable.
      await after.setBudget(name: 'Food', type: 'expense', amount: 400000);
      expect((await _storedBudgets(after)).single.amount, 400000);

      final int templateId = await after.insertRecurringTemplate(
        RecurringTemplatesCompanion.insert(
          type: 'expense',
          amount: 75000,
          categoryId: rows.single.categoryId,
          dayOfMonth: 5,
          createdAt: date,
        ),
      );
      expect(templateId, greaterThan(0));
    } finally {
      await after.close();
      dir.deleteSync(recursive: true);
    }
  });

  sqliteWidgetTest('tapping a category on the statistics tab sets its ceiling',
      (AppDatabase db, WidgetTester tester) async {
    await _insertFood(db, amount: 250000, date: DateTime.now());

    final StreamController<List<CategoryBudget>> budgets =
        StreamController<List<CategoryBudget>>.broadcast();
    addTearDown(budgets.close);

    await _pumpStatistics(tester, db, budgets: budgets.stream);
    budgets.add(const <CategoryBudget>[]);
    await _settle(tester);

    expect(find.widgetWithText(ListTile, 'Food'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // The pie chart labels its slices with the same names, so the row is
    // targeted as a list tile rather than by text alone.
    await tester.tap(find.widgetWithText(ListTile, 'Food'));
    await _settle(tester);

    expect(find.text('Budget for Food'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1000000');
    await tester.tap(find.text('Save'));
    await _settle(tester);

    // The dialog's job: the row is in the database.
    expect((await _storedBudgets(db)).single.amount, 1000000);

    // The screen's job: it draws what the stream carries, which is the same
    // row drift would have sent back.
    budgets.add(const <CategoryBudget>[
      CategoryBudget(name: 'Food', type: 'expense', amount: 1000000),
    ]);
    await _settle(tester);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('of ${_rp(1000000)}'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);

    await _unmount(tester);
  });

  sqliteWidgetTest('a ceiling already passed says so, and can be removed again',
      (AppDatabase db, WidgetTester tester) async {
    await _insertFood(db, amount: 1200000, date: DateTime.now());
    await db.setBudget(name: 'Food', type: 'expense', amount: 1000000);

    final StreamController<List<CategoryBudget>> budgets =
        StreamController<List<CategoryBudget>>.broadcast();
    addTearDown(budgets.close);

    await _pumpStatistics(tester, db, budgets: budgets.stream);
    budgets.add(const <CategoryBudget>[
      CategoryBudget(name: 'Food', type: 'expense', amount: 1000000),
    ]);
    await _settle(tester);

    expect(find.text('over by ${_rp(200000)}'), findsOneWidget);
    final LinearProgressIndicator bar =
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 1.0,
        reason: 'a passed ceiling fills the bar, it does not draw past its end');
    expect(bar.valueColor?.value, Colors.red);

    // Removing it from the same dialog drops the stored row...
    await tester.tap(find.widgetWithText(ListTile, 'Food'));
    await _settle(tester);
    await tester.tap(find.text('Remove'));
    await _settle(tester);
    expect(await _storedBudgets(db), isEmpty);

    // ...and the row loses its bar once the stream says so.
    budgets.add(const <CategoryBudget>[]);
    await _settle(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await _unmount(tester);
  });
}

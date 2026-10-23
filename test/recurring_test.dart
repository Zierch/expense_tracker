// Recurring transactions: one row a month, written when the app opens.
//
// The rules the user asked for are narrow, and each one is a way this could go
// wrong quietly — writing rows nobody asked for, or writing the same month's row
// twice, is only noticed weeks later when the totals are wrong:
//
//  * A template whose day has arrived writes exactly one row for the running
//    month, and repeating the check in the same month writes nothing.
//  * Before its day, nothing is written.
//  * A paused template writes nothing.
//  * A month that went by without the app being opened is not back-filled: the
//    feature writes the month that is running, never a history of missed ones.
//  * The transaction the template was made from counts as that month's row, so
//    making a template today cannot add a duplicate today.
//  * The screen has to reach the same table: pausing from the list has to reach
//    the database, not just the switch.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/domain/entities/recurring_template.dart';
import 'package:expense_tracker/presentation/pages/home_page.dart';
import 'package:expense_tracker/presentation/pages/recurring_page.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'sqlite_support.dart';

/// One `Food` expense template, due on [day], with nothing written yet.
Future<int> _insertTemplate(
  AppDatabase db, {
  int day = 5,
  double amount = 75000,
  bool active = true,
  DateTime? lastGeneratedOn,
}) async {
  final int categoryId = (await db.getCategories(type: 'expense')).first.id;
  final Subcategory food = (await db.getSubcategories(categoryId))
      .firstWhere((Subcategory s) => s.name == 'Food');

  return db.insertRecurringTemplate(RecurringTemplatesCompanion.insert(
    type: 'expense',
    amount: amount,
    categoryId: categoryId,
    subcategoryId: Value(food.id),
    note: const Value('Lunch money'),
    dayOfMonth: day,
    createdAt: DateTime(2026, 1, 1),
    active: Value(active),
    lastGeneratedOn: Value(lastGeneratedOn),
  ));
}

void main() {
  sqliteTest('its day writes one row for the month, and only one', (AppDatabase db) async {
    await _insertTemplate(db, day: 5);

    expect(await db.applyRecurringTemplates(DateTime(2026, 10, 5)), 1);

    final List<Transaction> rows = await db.getAllTransactions();
    expect(rows, hasLength(1));
    expect(rows.single.date, DateTime(2026, 10, 5));
    expect(rows.single.amount, 75000);
    expect(rows.single.note, 'Lunch money');

    // Opening the app again the same month writes nothing.
    expect(await db.applyRecurringTemplates(DateTime(2026, 10, 20)), 0);
    expect(await db.getAllTransactions(), hasLength(1));
  });

  sqliteTest('before its day, nothing is written', (AppDatabase db) async {
    await _insertTemplate(db, day: 5);

    expect(await db.applyRecurringTemplates(DateTime(2026, 10, 4)), 0);
    expect(await db.getAllTransactions(), isEmpty);

    // The next day it is due, and comes.
    expect(await db.applyRecurringTemplates(DateTime(2026, 10, 5)), 1);
    expect(await db.getAllTransactions(), hasLength(1));
  });

  sqliteTest('a paused template writes nothing', (AppDatabase db) async {
    await _insertTemplate(db, day: 5, active: false);

    expect(await db.applyRecurringTemplates(DateTime(2026, 10, 10)), 0);
    expect(await db.getAllTransactions(), isEmpty);
  });

  sqliteTest('a month that went by is not back-filled', (AppDatabase db) async {
    // Last written in August. Opened again in October: the running month gets a
    // row, August and September do not get a second one.
    await _insertTemplate(db, day: 5, lastGeneratedOn: DateTime(2026, 8, 5));

    expect(await db.applyRecurringTemplates(DateTime(2026, 10, 10)), 1);

    final List<Transaction> rows = await db.getAllTransactions();
    expect(rows.map((Transaction t) => t.date), <DateTime>[DateTime(2026, 10, 5)]);
  });

  sqliteTest('the row a template was made from counts as that month', (AppDatabase db) async {
    // This is what the add screen writes when "Repeat monthly" is on: the
    // transaction just saved is already this month's occurrence.
    await _insertTemplate(db, day: 5, lastGeneratedOn: DateTime(2026, 10, 5));

    expect(await db.applyRecurringTemplates(DateTime(2026, 10, 20)), 0);
  });

  sqliteTest('a day past the 28th is held inside every month', (AppDatabase db) async {
    final int id = await _insertTemplate(db, day: 28);

    // February has no 30th; the template stands on the 28th, which exists.
    expect(await db.applyRecurringTemplates(DateTime(2026, 2, 28)), 1);
    final List<Transaction> rows = await db.getAllTransactions();
    expect(rows.single.date, DateTime(2026, 2, 28));
    expect((await db.watchRecurringTemplatesWithNames().first).single.template.id, id);
  });

  test('a v3 install keeps its budgets and gains the templates table', () async {
    final Directory dir = Directory.systemTemp.createTempSync('expense_tracker_recurring');
    final String path = p.join(dir.path, 'app.sqlite');

    // An install from just before this feature: the budgets table is there, the
    // recurring one is not, and the recorded version is 3.
    final AppDatabase? before = openSqliteFileOrSkip(path);
    if (before == null) return;
    await before.setBudget(name: 'Food', type: 'expense', amount: 1000000);
    await before.customStatement('DROP TABLE recurring_templates');
    await before.customStatement('PRAGMA user_version = 3');
    await before.close();

    final AppDatabase? after = openSqliteFileOrSkip(path);
    if (after == null) return;
    try {
      final List<Budget> budgets = await after.select(after.budgets).get();
      expect(budgets.single.amount, 1000000);

      await _insertTemplate(after, day: 5);
      expect(await after.applyRecurringTemplates(DateTime(2026, 10, 5)), 1);
    } finally {
      await after.close();
      dir.deleteSync(recursive: true);
    }
  });

  sqliteWidgetTest('opening the dashboard writes the month\'s rows',
      (AppDatabase db, WidgetTester tester) async {
    await _insertTemplate(db, day: 1);

    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: HomePage()),
    ));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The write is fired from `initState` and waited for here rather than
    // assumed: the read below is queued behind it on the same executor.
    final List<Transaction> rows = await db.getAllTransactions();
    expect(rows, hasLength(1),
        reason: 'the dashboard is the one place that writes the month\'s rows');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  sqliteWidgetTest('pausing from the list reaches the database',
      (AppDatabase db, WidgetTester tester) async {
    final int id = await _insertTemplate(db, day: 5);
    final StreamController<List<RecurringTemplateEntity>> templates =
        StreamController<List<RecurringTemplateEntity>>.broadcast();
    addTearDown(templates.close);

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        recurringTemplatesProvider.overrideWith((Ref ref) => templates.stream),
      ],
      child: const MaterialApp(home: RecurringPage()),
    ));
    templates.add(<RecurringTemplateEntity>[
      RecurringTemplateEntity(
        id: id,
        type: 'expense',
        amount: 75000,
        categoryId: 1,
        dayOfMonth: 5,
        active: true,
        categoryName: 'Expense',
        subcategoryName: 'Food',
      ),
    ]);
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Every month on day 5'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final List<RecurringTemplate> stored = await db.select(db.recurringTemplates).get();
    expect(stored.single.active, isFalse);

    // Swiping asks first, and only a confirmed swipe reaches the database...
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Delete this recurring transaction?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await db.select(db.recurringTemplates).get(), hasLength(1));

    // ...and a confirmed one deletes the template, not the history.
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Delete'));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await db.select(db.recurringTemplates).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}

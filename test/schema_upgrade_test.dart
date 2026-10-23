// Schema 5 drops the budget and recurring-templates tables.
//
// Those two features were withdrawn, and the tables go with them — but a phone
// that opened v1.7.0 recorded version 4, so the only safe way out is forward:
// version 5, with an explicit drop. This test pins what that costs and what it
// does not:
//
//  * The two tables are gone afterwards, so nothing can read them by accident.
//  * The transactions are all still there, including rows those features wrote —
//    a generated row was an ordinary transaction, not a reference.
//  * The install can come from version 2 or 3 as well, where one or both of the
//    tables were never created, so the drop has to tolerate a missing table.

import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'sqlite_support.dart';

Future<Set<String>> _tables(AppDatabase db) async {
  final List<QueryRow> rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((QueryRow row) => row.read<String>('name')).toSet();
}

Future<int> _insertExpense(AppDatabase db, double amount) async {
  final int categoryId = (await db.getCategories(type: 'expense')).first.id;
  final Subcategory food = (await db.getSubcategories(categoryId))
      .firstWhere((Subcategory s) => s.name == 'Food');
  return db.insertTransaction(TransactionsCompanion.insert(
    type: 'expense',
    amount: amount,
    categoryId: categoryId,
    subcategoryId: Value(food.id),
    date: DateTime(2026, 10, 4),
    createdAt: Value(DateTime(2026, 10, 4)),
  ));
}

void main() {
  test('a v4 install loses the two tables and keeps its transactions', () async {
    final Directory dir = Directory.systemTemp.createTempSync('expense_tracker_from_v4');
    final String path = p.join(dir.path, 'app.sqlite');

    final AppDatabase? before = openSqliteFileOrSkip(path);
    if (before == null) return;

    final int rowId = await _insertExpense(before, 250000);

    // What v1.7.0 left behind: the two tables, with a row in each, and a
    // recorded version of 4. The rows matter — dropping the table has to take
    // them and nothing else.
    await before.customStatement(
      'CREATE TABLE budgets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, amount REAL)',
    );
    await before.customStatement("INSERT INTO budgets (name, type, amount) VALUES ('Food', 'expense', 1000000)");
    await before.customStatement(
      'CREATE TABLE recurring_templates (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT)',
    );
    await before.customStatement("INSERT INTO recurring_templates (type) VALUES ('expense')");
    await before.customStatement('PRAGMA user_version = 4');
    await before.close();

    final AppDatabase? after = openSqliteFileOrSkip(path);
    if (after == null) return;
    try {
      expect(await _tables(after), isNot(contains('budgets')));
      expect(await _tables(after), isNot(contains('recurring_templates')));

      final List<Transaction> rows = await after.getAllTransactions();
      expect(rows.map((Transaction t) => t.id), <int>[rowId]);
      expect(rows.single.amount, 250000);

      // And the install is now at the version this build declares, so the next
      // upgrade starts from the right place.
      final QueryRow version =
          await after.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 5);
    } finally {
      await after.close();
      dir.deleteSync(recursive: true);
    }
  });

  test('a v3 install, which had budgets and no templates, upgrades too', () async {
    final Directory dir = Directory.systemTemp.createTempSync('expense_tracker_from_v3');
    final String path = p.join(dir.path, 'app.sqlite');

    final AppDatabase? before = openSqliteFileOrSkip(path);
    if (before == null) return;

    final int rowId = await _insertExpense(before, 120000);
    await before.customStatement(
      'CREATE TABLE budgets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, amount REAL)',
    );
    await before.customStatement('PRAGMA user_version = 3');
    await before.close();

    final AppDatabase? after = openSqliteFileOrSkip(path);
    if (after == null) return;
    try {
      expect((await after.getAllTransactions()).map((Transaction t) => t.id), <int>[rowId]);
      // The table that was there is dropped; the one that never existed is
      // skipped rather than being an error.
      expect(await _tables(after), isNot(contains('budgets')));
      expect(await _tables(after), isNot(contains('recurring_templates')));
    } finally {
      await after.close();
      dir.deleteSync(recursive: true);
    }
  });

  test('a v2 install, which never had either table, upgrades without complaint', () async {
    final Directory dir = Directory.systemTemp.createTempSync('expense_tracker_from_v2');
    final String path = p.join(dir.path, 'app.sqlite');

    final AppDatabase? before = openSqliteFileOrSkip(path);
    if (before == null) return;

    final int rowId = await _insertExpense(before, 90000);
    await before.customStatement('PRAGMA user_version = 2');
    await before.close();

    final AppDatabase? after = openSqliteFileOrSkip(path);
    if (after == null) return;
    try {
      expect((await after.getAllTransactions()).map((Transaction t) => t.id), <int>[rowId]);
      expect(await _tables(after), isNot(contains('budgets')));
      expect(await _tables(after), isNot(contains('recurring_templates')));
    } finally {
      await after.close();
      dir.deleteSync(recursive: true);
    }
  });
}

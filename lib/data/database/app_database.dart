import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'app_database.g.dart';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get type => text().withLength(min: 1, max: 10)(); // 'income' | 'expense'
}

class Subcategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get name => text().withLength(min: 1, max: 50)();
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text().withLength(min: 1, max: 10)();
  RealColumn get amount => real()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get subcategoryId => integer().nullable().references(Subcategories, #id)();
  TextColumn get note => text().nullable()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
}

/// A monthly spending ceiling, per category.
///
/// Keyed by the *name* the breakdown already shows — `subcategoryName ??
/// categoryName`, the string `getExpenseByCategory` puts on the statistics list
/// and in the PDF — rather than by id. Two subcategories may share a name, and a
/// budget held by id would then have to pick one of the rows it measures; held
/// by name it measures exactly the row the user tapped. There is no rename in
/// the app, so the name is stable; if renaming ever lands, this table needs the
/// ids and a migration that fills them.
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get type => text().withLength(min: 1, max: 10)(); // 'income' | 'expense'
  RealColumn get amount => real()();

  /// One ceiling per category: the database refuses a second row for the same
  /// pair even if a caller forgets to replace the first.
  @override
  List<Set<Column>> get uniqueKeys => [
        {name, type},
      ];
}

/// A transaction that comes back every month, on the same day.
///
/// [dayOfMonth] is held between 1 and 28 so that every month has the day,
/// February included. [lastGeneratedOn] is the day this month's row was written:
/// null until it happens once, and the reason opening the app twice in a month
/// cannot add the row twice. A month that went by without the app being opened
/// is not back-filled — the row is written for the month that is running, or not
/// at all.
class RecurringTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text().withLength(min: 1, max: 10)(); // 'income' | 'expense'
  RealColumn get amount => real()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get subcategoryId => integer().nullable().references(Subcategories, #id)();
  TextColumn get note => text().nullable()();
  IntColumn get dayOfMonth => integer()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastGeneratedOn => dateTime().nullable()();
}

@DriftDatabase(tables: [Categories, Subcategories, Transactions, Budgets, RecurringTemplates])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Opens the database on [executor] instead of the on-device file.
  ///
  /// Tests pass `NativeDatabase.memory()` so the real schema and the real `isBetween`
  /// comparisons run against a real SQLite. A stand-in repository cannot do that job:
  /// it would have to reimplement the date predicate, and would then agree with
  /// `MonthRange.contains` by construction rather than by being correct.
  @visibleForTesting
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _seedData();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.createTable(categories);
          await m.createTable(subcategories);
          await m.addColumn(transactions, transactions.categoryId);
          await m.addColumn(transactions, transactions.subcategoryId);
          await _seedData();
        }
        // v3 only adds a table: no existing row is touched, so an install that
        // upgrades keeps every transaction it had.
        if (from < 3) {
          await m.createTable(budgets);
        }
        // v4 is the same trade: one new table, nothing existing rewritten.
        if (from < 4) {
          await m.createTable(recurringTemplates);
        }
      },
    );
  }

  /// Seeds only the default categories and subcategories.
  /// No sample transactions are inserted, so a fresh install starts empty.
  Future<void> _seedData() async {
    // Income category + subcategories
    final incomeCatId = await into(categories).insert(CategoriesCompanion.insert(
      name: 'Income',
      type: 'income',
    ));
    await into(subcategories).insert(SubcategoriesCompanion.insert(
      categoryId: incomeCatId,
      name: 'Salary',
    ));
    await into(subcategories).insert(SubcategoriesCompanion.insert(
      categoryId: incomeCatId,
      name: 'Freelance',
    ));
    await into(subcategories).insert(SubcategoriesCompanion.insert(
      categoryId: incomeCatId,
      name: 'Investment',
    ));
    await into(subcategories).insert(SubcategoriesCompanion.insert(
      categoryId: incomeCatId,
      name: 'Allowance',
    ));
    await into(subcategories).insert(SubcategoriesCompanion.insert(
      categoryId: incomeCatId,
      name: 'Bonus',
    ));
    await into(subcategories).insert(SubcategoriesCompanion.insert(
      categoryId: incomeCatId,
      name: 'Gift',
    ));

    // Expense category + subcategories
    final expenseCatId = await into(categories).insert(CategoriesCompanion.insert(
      name: 'Expense',
      type: 'expense',
    ));
    await into(subcategories).insert(SubcategoriesCompanion.insert(
      categoryId: expenseCatId,
      name: 'Food',
    ));
    await into(subcategories).insert(SubcategoriesCompanion.insert(
      categoryId: expenseCatId,
      name: 'Other Needs',
    ));
    await into(subcategories).insert(SubcategoriesCompanion.insert(
      categoryId: expenseCatId,
      name: 'Data/Internet Package',
    ));
  }

  // Transaction queries
  Future<List<Transaction>> getAllTransactions() => select(transactions).get();
  Stream<List<Transaction>> watchAllTransactions() => select(transactions).watch();

  Future<List<Transaction>> getTransactionsByDateRange(DateTime start, DateTime end) {
    return (select(transactions)
          ..where((t) => t.date.isBetween(Variable(start), Variable(end)))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }

  Future<int> insertTransaction(TransactionsCompanion transaction) => into(transactions).insert(transaction);
  Future<bool> updateTransaction(TransactionsCompanion transaction) => update(transactions).replace(transaction);
  Future<int> deleteTransaction(int id) => (delete(transactions)..where((t) => t.id.equals(id))).go();

  Future<double> getTotalIncome({DateTime? start, DateTime? end}) async {
    var query = select(transactions)..where((t) => t.type.equals('income'));
    if (start != null && end != null) {
      query.where((t) => t.date.isBetween(Variable(start), Variable(end)));
    }
    final rows = await query.get();
    return rows.fold<double>(0.0, (sum, t) => sum + t.amount);
  }

  Future<double> getTotalExpense({DateTime? start, DateTime? end}) async {
    var query = select(transactions)..where((t) => t.type.equals('expense'));
    if (start != null && end != null) {
      query.where((t) => t.date.isBetween(Variable(start), Variable(end)));
    }
    final rows = await query.get();
    return rows.fold<double>(0.0, (sum, t) => sum + t.amount);
  }

  Future<Map<String, double>> getExpenseByCategory({DateTime? start, DateTime? end}) async {
    var query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      leftOuterJoin(subcategories, subcategories.id.equalsExp(transactions.subcategoryId)),
    ])
      ..where(transactions.type.equals('expense'));

    if (start != null && end != null) {
      query.where(transactions.date.isBetween(Variable(start), Variable(end)));
    }

    final rows = await query.get();
    final Map<String, double> result = {};
    for (final row in rows) {
      final key = row.readTableOrNull(subcategories)?.name ?? row.readTable(categories).name;
      result[key] = (result[key] ?? 0) + row.readTable(transactions).amount;
    }
    return result;
  }

  Future<Map<String, double>> getIncomeByCategory({DateTime? start, DateTime? end}) async {
    var query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      leftOuterJoin(subcategories, subcategories.id.equalsExp(transactions.subcategoryId)),
    ])
      ..where(transactions.type.equals('income'));

    if (start != null && end != null) {
      query.where(transactions.date.isBetween(Variable(start), Variable(end)));
    }

    final rows = await query.get();
    final Map<String, double> result = {};
    for (final row in rows) {
      final key = row.readTableOrNull(subcategories)?.name ?? row.readTable(categories).name;
      result[key] = (result[key] ?? 0) + row.readTable(transactions).amount;
    }
    return result;
  }

  Future<List<Category>> getCategories({String? type}) async {
    var query = select(categories);
    if (type != null) {
      query.where((c) => c.type.equals(type));
    }
    return query.get();
  }

  Future<List<Subcategory>> getSubcategories(int categoryId) {
    return (select(subcategories)..where((s) => s.categoryId.equals(categoryId))).get();
  }

  // Budget queries

  Stream<List<Budget>> watchBudgets() => select(budgets).watch();

  /// One ceiling per (type, name): setting a second one replaces the first
  /// rather than stacking, which is what keeps a category showing a single bar.
  ///
  /// In one transaction on purpose: a delete that landed without its insert
  /// would leave the category with no ceiling at all, which is not what the
  /// user asked for by tapping Save.
  Future<void> setBudget({
    required String name,
    required String type,
    required double amount,
  }) {
    return transaction(() async {
      await clearBudget(name: name, type: type);
      await into(budgets).insert(
        BudgetsCompanion.insert(name: name, type: type, amount: amount),
      );
    });
  }

  Future<void> clearBudget({required String name, required String type}) {
    return (delete(budgets)..where((b) => b.name.equals(name) & b.type.equals(type))).go();
  }

  // Recurring template queries

  Stream<List<RecurringTemplateWithNames>> watchRecurringTemplatesWithNames() {
    final query = select(recurringTemplates).join([
      innerJoin(categories, categories.id.equalsExp(recurringTemplates.categoryId)),
      leftOuterJoin(subcategories, subcategories.id.equalsExp(recurringTemplates.subcategoryId)),
    ]);
    return query.watch().map((List<TypedResult> rows) => rows
        .map((TypedResult row) => RecurringTemplateWithNames(
              template: row.readTable(recurringTemplates),
              categoryName: row.readTable(categories).name,
              subcategoryName: row.readTableOrNull(subcategories)?.name,
            ))
        .toList()
      ..sort((RecurringTemplateWithNames a, RecurringTemplateWithNames b) =>
          a.template.dayOfMonth.compareTo(b.template.dayOfMonth)));
  }

  Future<int> insertRecurringTemplate(RecurringTemplatesCompanion template) =>
      into(recurringTemplates).insert(template);

  Future<void> setRecurringTemplateActive(int id, bool active) {
    return (update(recurringTemplates)..where((t) => t.id.equals(id)))
        .write(RecurringTemplatesCompanion(active: Value(active)));
  }

  Future<int> deleteRecurringTemplate(int id) {
    return (delete(recurringTemplates)..where((t) => t.id.equals(id))).go();
  }

  /// Writes this month's row for every active template whose day has arrived.
  ///
  /// Returns how many rows were written. Nothing is written for a month that has
  /// gone by, and nothing is written twice in the same month — that is what
  /// `lastGeneratedOn` is for. A row the user deleted stays deleted until the
  /// next month, because this method only ever looks at that column, never at
  /// the transactions themselves.
  Future<int> applyRecurringTemplates(DateTime now) async {
    final List<RecurringTemplate> templates =
        await (select(recurringTemplates)..where((t) => t.active.equals(true))).get();

    int written = 0;
    for (final RecurringTemplate template in templates) {
      final DateTime? last = template.lastGeneratedOn;
      if (last != null && last.year == now.year && last.month == now.month) continue;
      if (now.day < template.dayOfMonth) continue;

      await into(transactions).insert(TransactionsCompanion.insert(
        type: template.type,
        amount: template.amount,
        categoryId: template.categoryId,
        subcategoryId: Value(template.subcategoryId),
        note: Value(template.note),
        date: DateTime(now.year, now.month, template.dayOfMonth),
        createdAt: Value(now),
      ));
      await (update(recurringTemplates)..where((t) => t.id.equals(template.id)))
          .write(RecurringTemplatesCompanion(lastGeneratedOn: Value(now)));
      written++;
    }
    return written;
  }

  /// Newest first, and repeatable.
  ///
  /// `date` is a calendar day rather than an instant (`add_transaction_page` stores it
  /// that way), so a day's rows all tie on it. Without tie-breakers SQLite is free to
  /// return them in any order, and the dashboard sorts in memory with `List.sort`,
  /// which is not stable — so the same day's rows came back in whatever order SQLite
  /// and the sort happened to produce, and the list looked shuffled between rebuilds.
  List<OrderingTerm> get _newestFirst => [
        OrderingTerm.desc(transactions.date),
        OrderingTerm.desc(transactions.createdAt),
        OrderingTerm.desc(transactions.id),
      ];

  Future<List<TransactionWithNames>> getTransactionsWithJoinedNames() async {
    final rows = await (select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      leftOuterJoin(subcategories, subcategories.id.equalsExp(transactions.subcategoryId)),
    ])
          ..orderBy(_newestFirst))
        .get();
    return rows.map((row) {
      return TransactionWithNames(
        transaction: row.readTable(transactions),
        categoryName: row.readTable(categories).name,
        subcategoryName: row.readTableOrNull(subcategories)?.name,
      );
    }).toList();
  }

  Stream<List<TransactionWithNames>> watchTransactionsWithJoinedNames() {
    return (select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      leftOuterJoin(subcategories, subcategories.id.equalsExp(transactions.subcategoryId)),
    ])
          ..orderBy(_newestFirst))
        .watch()
        .map((rows) {
      return rows.map((row) {
        return TransactionWithNames(
          transaction: row.readTable(transactions),
          categoryName: row.readTable(categories).name,
          subcategoryName: row.readTableOrNull(subcategories)?.name,
        );
      }).toList();
    });
  }

  Future<List<TransactionWithNames>> getTransactionsByDateRangeWithNames(DateTime start, DateTime end) async {
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      leftOuterJoin(subcategories, subcategories.id.equalsExp(transactions.subcategoryId)),
    ]);
    query.where(transactions.date.isBetween(Variable(start), Variable(end)));
    final rows = await query.get();
    return rows.map((row) {
      return TransactionWithNames(
        transaction: row.readTable(transactions),
        categoryName: row.readTable(categories).name,
        subcategoryName: row.readTableOrNull(subcategories)?.name,
      );
    }).toList()
      ..sort((a, b) => b.transaction.date.compareTo(a.transaction.date));
  }
}

// Joined transaction result with category/subcategory names
class TransactionWithNames {
  final Transaction transaction;
  final String categoryName;
  final String? subcategoryName;

  TransactionWithNames({
    required this.transaction,
    required this.categoryName,
    this.subcategoryName,
  });
}

class RecurringTemplateWithNames {
  final RecurringTemplate template;
  final String categoryName;
  final String? subcategoryName;

  RecurringTemplateWithNames({
    required this.template,
    required this.categoryName,
    this.subcategoryName,
  });
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'expense_tracker.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

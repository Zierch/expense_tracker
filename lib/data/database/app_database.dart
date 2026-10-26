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
  TextColumn get type =>
      text().withLength(min: 1, max: 10)(); // 'income' | 'expense'
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
  IntColumn get subcategoryId =>
      integer().nullable().references(Subcategories, #id)();
  TextColumn get note => text().nullable()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
}

@DriftDatabase(tables: [Categories, Subcategories, Transactions])
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
  int get schemaVersion => 5;

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
        // v3 and v4 added the budgets and recurring-templates tables; both
        // features were withdrawn and the tables go with them. Dropped by name
        // because the table classes are gone, and `IF EXISTS` because an install
        // can arrive here from 2 or 3, where those tables were never made.
        //
        // Going up, never down: a phone that opened v1.7.0 recorded version 4,
        // and a schema that stepped backwards would leave drift with no upgrade
        // path at all. Every transaction survives this — only the ceilings and
        // the repeat rules are dropped, and rows those rules already wrote are
        // ordinary transactions.
        if (from < 5) {
          await customStatement('DROP TABLE IF EXISTS budgets');
          await customStatement('DROP TABLE IF EXISTS recurring_templates');
        }
      },
    );
  }

  /// Seeds only the default categories and subcategories.
  /// No sample transactions are inserted, so a fresh install starts empty.
  Future<void> _seedData() async {
    // Income category + subcategories
    final incomeCatId =
        await into(categories).insert(CategoriesCompanion.insert(
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
    final expenseCatId =
        await into(categories).insert(CategoriesCompanion.insert(
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
  Stream<List<Transaction>> watchAllTransactions() =>
      select(transactions).watch();

  Future<List<Transaction>> getTransactionsByDateRange(
      DateTime start, DateTime end) {
    return (select(transactions)
          ..where((t) => t.date.isBetween(Variable(start), Variable(end)))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }

  Future<int> insertTransaction(TransactionsCompanion transaction) =>
      into(transactions).insert(transaction);
  Future<bool> updateTransaction(TransactionsCompanion transaction) =>
      update(transactions).replace(transaction);
  Future<int> deleteTransaction(int id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

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

  Future<Map<String, double>> getExpenseByCategory(
      {DateTime? start, DateTime? end}) async {
    var query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      leftOuterJoin(subcategories,
          subcategories.id.equalsExp(transactions.subcategoryId)),
    ])
      ..where(transactions.type.equals('expense'));

    if (start != null && end != null) {
      query.where(transactions.date.isBetween(Variable(start), Variable(end)));
    }

    final rows = await query.get();
    final Map<String, double> result = {};
    for (final row in rows) {
      final key = row.readTableOrNull(subcategories)?.name ??
          row.readTable(categories).name;
      result[key] = (result[key] ?? 0) + row.readTable(transactions).amount;
    }
    return result;
  }

  Future<Map<String, double>> getIncomeByCategory(
      {DateTime? start, DateTime? end}) async {
    var query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      leftOuterJoin(subcategories,
          subcategories.id.equalsExp(transactions.subcategoryId)),
    ])
      ..where(transactions.type.equals('income'));

    if (start != null && end != null) {
      query.where(transactions.date.isBetween(Variable(start), Variable(end)));
    }

    final rows = await query.get();
    final Map<String, double> result = {};
    for (final row in rows) {
      final key = row.readTableOrNull(subcategories)?.name ??
          row.readTable(categories).name;
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
    return (select(subcategories)
          ..where((s) => s.categoryId.equals(categoryId)))
        .get();
  }

  // Import queries

  /// The id of a category with this name and type, making one when the local
  /// database has never seen it.
  ///
  /// An import brings names, not ids: the backup was written by an install whose
  /// categories may have been renamed, added to, or seeded differently. Matched
  /// on name *and* type because "Gift" is a legitimate name on both sides, and on
  /// the exact name because a "restore" that quietly renamed anything would be
  /// lying about what it restored.
  Future<int> findOrCreateCategory(String name, String type) async {
    final Category? existing = await (select(categories)
          ..where((c) => c.name.equals(name) & c.type.equals(type))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return existing.id;

    return into(categories)
        .insert(CategoriesCompanion.insert(name: name, type: type));
  }

  Future<int> findOrCreateSubcategory(String name, int categoryId) async {
    final Subcategory? existing = await (select(subcategories)
          ..where((s) => s.name.equals(name) & s.categoryId.equals(categoryId))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return existing.id;

    return into(subcategories).insert(
      SubcategoriesCompanion.insert(name: name, categoryId: categoryId),
    );
  }

  /// Whether a row with these exact values is already stored on [date]'s day.
  ///
  /// The backup carries the ids the rows had in the install that wrote it, and
  /// those ids mean nothing here — a fresh install numbers its rows from one, so
  /// importing by id would either collide or leave holes. Identity is therefore
  /// the content: two rows are the same transaction when every field the user
  /// can see matches. A second import of the same file therefore adds nothing,
  /// which is what makes retrying a restore safe.
  ///
  /// The day is compared as a *range*, not as an instant. A transaction is a
  /// calendar day, but rows written by older versions of the app still carry the
  /// time of day they were entered at, while an import always normalises to
  /// midnight — so matching midnight exactly would miss the very row it is meant
  /// to recognise and write a second copy of it. Semantics here must match
  /// [MonthRange]'s: the unit is the day.
  Future<bool> hasMatchingTransaction({
    required DateTime date,
    required String type,
    required double amount,
    required int categoryId,
    int? subcategoryId,
    String? note,
  }) async {
    final DateTime dayStart = DateTime(date.year, date.month, date.day);
    final DateTime dayEnd = DateTime(date.year, date.month, date.day + 1);

    final query = select(transactions)
      ..where((t) =>
          t.date.isBiggerOrEqualValue(dayStart) &
          t.date.isSmallerThanValue(dayEnd) &
          t.type.equals(type) &
          t.amount.equals(amount) &
          t.categoryId.equals(categoryId) &
          (subcategoryId == null
              ? t.subcategoryId.isNull()
              : t.subcategoryId.equals(subcategoryId)) &
          (note == null ? t.note.isNull() : t.note.equals(note)))
      ..limit(1);

    return (await query.getSingleOrNull()) != null;
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
      leftOuterJoin(subcategories,
          subcategories.id.equalsExp(transactions.subcategoryId)),
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
      leftOuterJoin(subcategories,
          subcategories.id.equalsExp(transactions.subcategoryId)),
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

  Future<List<TransactionWithNames>> getTransactionsByDateRangeWithNames(
      DateTime start, DateTime end) async {
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      leftOuterJoin(subcategories,
          subcategories.id.equalsExp(transactions.subcategoryId)),
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

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'expense_tracker.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

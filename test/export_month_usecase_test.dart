import 'package:expense_tracker/domain/entities/category_budget.dart';
import 'package:expense_tracker/domain/entities/recurring_template.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/usecases/export_month_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the Drift repository.
///
/// Grouping mirrors `AppDatabase.getExpenseByCategory` /
/// `getIncomeByCategory`, which key on `subcategoryName ?? categoryName`.
class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository(this.transactions);

  final List<TransactionEntity> transactions;

  List<TransactionEntity> _inRange(DateTime? start, DateTime? end) {
    return transactions.where((TransactionEntity transaction) {
      if (start != null && transaction.date.isBefore(start)) return false;
      if (end != null && transaction.date.isAfter(end)) return false;
      return true;
    }).toList();
  }

  double _totalFor(List<TransactionEntity> rows, String type) => rows
      .where((TransactionEntity transaction) => transaction.type == type)
      .fold<double>(0, (double sum, TransactionEntity t) => sum + t.amount);

  Map<String, double> _breakdownFor(
    List<TransactionEntity> rows,
    String type,
  ) {
    final Map<String, double> result = <String, double>{};
    for (final TransactionEntity transaction
        in rows.where((TransactionEntity t) => t.type == type)) {
      result[transaction.displayCategory] =
          (result[transaction.displayCategory] ?? 0) + transaction.amount;
    }
    return result;
  }

  @override
  Future<List<TransactionEntity>> getTransactionsByDateRange(
    DateTime start,
    DateTime end,
  ) async =>
      _inRange(start, end);

  @override
  Future<double> getTotalIncome({DateTime? start, DateTime? end}) async =>
      _totalFor(_inRange(start, end), 'income');

  @override
  Future<double> getTotalExpense({DateTime? start, DateTime? end}) async =>
      _totalFor(_inRange(start, end), 'expense');

  @override
  Future<Map<String, double>> getIncomeByCategory({
    DateTime? start,
    DateTime? end,
  }) async =>
      _breakdownFor(_inRange(start, end), 'income');

  // No ceilings: nothing in these tests reads or writes one, so the fake
  // reports that there are none rather than pretending to store them.
  @override
  Stream<List<CategoryBudget>> watchBudgets() =>
      Stream<List<CategoryBudget>>.value(const <CategoryBudget>[]);

  @override
  Future<void> setBudget({required String name, required String type, required double amount}) async {}

  @override
  Future<void> clearBudget({required String name, required String type}) async {}
  // No templates: none of these tests launch the dashboard, which is what
  // writes a row, and none of them read the list.
  @override
  Stream<List<RecurringTemplateEntity>> watchRecurringTemplates() =>
      Stream<List<RecurringTemplateEntity>>.value(const <RecurringTemplateEntity>[]);

  @override
  Future<int> addRecurringTemplate(RecurringTemplateEntity template) async => 0;

  @override
  Future<void> setRecurringTemplateActive(int id, bool active) async {}

  @override
  Future<int> deleteRecurringTemplate(int id) async => 0;

  @override
  Future<int> applyRecurringTemplates(DateTime now) async => 0;


  @override
  Future<Map<String, double>> getExpenseByCategory({
    DateTime? start,
    DateTime? end,
  }) async =>
      _breakdownFor(_inRange(start, end), 'expense');

  @override
  Future<List<TransactionEntity>> getAllTransactions() async =>
      List<TransactionEntity>.of(transactions);

  @override
  Stream<List<TransactionEntity>> watchAllTransactions() =>
      Stream<List<TransactionEntity>>.value(transactions);

  @override
  Future<int> insertTransaction(TransactionEntity transaction) async => 0;

  @override
  Future<bool> updateTransaction(TransactionEntity transaction) async => true;

  @override
  Future<int> deleteTransaction(int id) async => 1;
}

TransactionEntity _transaction({
  required int id,
  required String type,
  required double amount,
  required DateTime date,
  String? categoryName,
  String? subcategoryName,
}) {
  return TransactionEntity(
    id: id,
    type: type,
    amount: amount,
    categoryId: 1,
    subcategoryId: subcategoryName == null ? null : 2,
    categoryName: categoryName,
    subcategoryName: subcategoryName,
    date: date,
    createdAt: date,
  );
}

void main() {
  final DateTime january = DateTime(2026, 1);

  late List<TransactionEntity> rows;

  setUp(() {
    rows = <TransactionEntity>[
      _transaction(
        id: 3,
        type: 'expense',
        amount: 100000,
        date: DateTime(2026, 1, 20, 9),
        categoryName: 'Food',
        subcategoryName: 'Groceries',
      ),
      _transaction(
        id: 1,
        type: 'income',
        amount: 5000000,
        date: DateTime(2026, 1, 2, 8),
        categoryName: 'Salary',
      ),
      _transaction(
        id: 2,
        type: 'expense',
        amount: 40000,
        date: DateTime(2026, 1, 5, 19),
        categoryName: 'Food',
        subcategoryName: 'Eating Out',
      ),
      // Outside the exported month — must be excluded.
      _transaction(
        id: 4,
        type: 'expense',
        amount: 999999,
        date: DateTime(2026, 2, 1),
        categoryName: 'Food',
      ),
    ];
  });

  ExportMonthUseCase buildUseCase() =>
      ExportMonthUseCase(_FakeTransactionRepository(rows));

  test('names the file after the month and records the period', () async {
    final MonthExport export = await buildUseCase().call(january);

    expect(export.fileName, 'expense-tracker-2026-01.json');
    expect(export.monthLabel, 'January 2026');

    final Map<String, dynamic> period =
        export.json['period'] as Map<String, dynamic>;
    expect(period['year'], 2026);
    expect(period['month'], 1);
    expect(period['startDate'], '2026-01-01');
    expect(period['endDate'], '2026-01-31');
  });

  test('excludes transactions from other months', () async {
    final MonthExport export = await buildUseCase().call(january);

    expect(export.transactionCount, 3);
    expect(export.totalIncome, 5000000);
    expect(export.totalExpense, 140000);
  });

  test('includes the last day of the month', () async {
    rows.add(
      _transaction(
        id: 9,
        type: 'expense',
        amount: 7000,
        date: DateTime(2026, 1, 31, 23, 59, 59),
        categoryName: 'Transport',
      ),
    );

    final MonthExport export = await buildUseCase().call(january);

    expect(export.transactionCount, 4);
    expect(export.totalExpense, 147000);
  });

  test('includes a transaction in the final microsecond of the month', () async {
    rows.add(
      _transaction(
        id: 10,
        type: 'expense',
        amount: 500,
        date: DateTime(2026, 1, 31, 23, 59, 59, 999, 999),
        categoryName: 'Transport',
      ),
    );

    final MonthExport export = await buildUseCase().call(january);

    expect(export.transactionCount, 4);
    expect(export.totalExpense, 140500);
  });

  test('excludes midnight of the following month', () async {
    rows.add(
      _transaction(
        id: 11,
        type: 'expense',
        amount: 12345,
        date: DateTime(2026, 2, 1),
        categoryName: 'Transport',
      ),
    );

    final MonthExport export = await buildUseCase().call(january);

    expect(export.transactionCount, 3);
    expect(export.totalExpense, 140000);
  });

  test('summary reports balance and category breakdowns', () async {
    final MonthExport export = await buildUseCase().call(january);
    final Map<String, dynamic> summary =
        export.json['summary'] as Map<String, dynamic>;

    expect(summary['totalIncome'], 5000000);
    expect(summary['totalExpense'], 140000);
    expect(summary['balance'], 4860000);

    expect(summary['incomeByCategory'], <Map<String, dynamic>>[
      <String, dynamic>{'category': 'Salary', 'total': 5000000.0},
    ]);

    // Largest spend first.
    expect(summary['expenseByCategory'], <Map<String, dynamic>>[
      <String, dynamic>{'category': 'Groceries', 'total': 100000.0},
      <String, dynamic>{'category': 'Eating Out', 'total': 40000.0},
    ]);
  });

  test('lists transactions in chronological order with ISO dates', () async {
    final MonthExport export = await buildUseCase().call(january);
    final List<dynamic> transactions =
        export.json['transactions'] as List<dynamic>;

    expect(
      transactions.map((dynamic row) => (row as Map<String, dynamic>)['id']),
      <int>[1, 2, 3],
    );

    final Map<String, dynamic> first = transactions.first as Map<String, dynamic>;
    expect(first['date'], '2026-01-02');
    expect(first['type'], 'income');
    expect(first['category'], 'Salary');
    expect(first['amount'], 5000000.0);

    final Map<String, dynamic> second = transactions[1] as Map<String, dynamic>;
    expect(second['subcategory'], 'Eating Out');
    expect(second['category'], 'Food');
  });

  test('handles an empty month', () async {
    final MonthExport export = await buildUseCase().call(DateTime(2025, 6));

    expect(export.transactionCount, 0);
    expect(export.totalIncome, 0);
    expect(export.totalExpense, 0);
    expect(export.json['transactions'], isEmpty);
    expect(export.fileName, 'expense-tracker-2025-06.json');
  });
}

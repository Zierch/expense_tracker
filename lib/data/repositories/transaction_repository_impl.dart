import 'package:drift/drift.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/domain/entities/category_budget.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/entities/recurring_template.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  final AppDatabase _database;

  TransactionRepositoryImpl(this._database);

  @override
  Future<List<TransactionEntity>> getAllTransactions() async {
    final rows = await _database.getTransactionsWithJoinedNames();
    return rows.map(_toEntity).toList();
  }

  @override
  Stream<List<TransactionEntity>> watchAllTransactions() {
    return _database.watchTransactionsWithJoinedNames().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<List<TransactionEntity>> getTransactionsByDateRange(DateTime start, DateTime end) async {
    final rows = await _database.getTransactionsByDateRangeWithNames(start, end);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<int> insertTransaction(TransactionEntity transaction) {
    return _database.insertTransaction(TransactionsCompanion(
      type: Value(transaction.type),
      amount: Value(transaction.amount),
      categoryId: Value(transaction.categoryId),
      subcategoryId: Value(transaction.subcategoryId),
      note: Value(transaction.note),
      date: Value(transaction.date),
    ));
  }

  @override
  Future<bool> updateTransaction(TransactionEntity transaction) {
    return _database.updateTransaction(TransactionsCompanion(
      id: Value(transaction.id),
      type: Value(transaction.type),
      amount: Value(transaction.amount),
      categoryId: Value(transaction.categoryId),
      subcategoryId: Value(transaction.subcategoryId),
      note: Value(transaction.note),
      date: Value(transaction.date),
    ));
  }

  @override
  Future<int> deleteTransaction(int id) {
    return _database.deleteTransaction(id);
  }

  @override
  Future<double> getTotalIncome({DateTime? start, DateTime? end}) {
    return _database.getTotalIncome(start: start, end: end);
  }

  @override
  Future<double> getTotalExpense({DateTime? start, DateTime? end}) {
    return _database.getTotalExpense(start: start, end: end);
  }

  @override
  Future<Map<String, double>> getExpenseByCategory({DateTime? start, DateTime? end}) {
    return _database.getExpenseByCategory(start: start, end: end);
  }

  @override
  Future<Map<String, double>> getIncomeByCategory({DateTime? start, DateTime? end}) {
    return _database.getIncomeByCategory(start: start, end: end);
  }

  @override
  Stream<List<CategoryBudget>> watchBudgets() {
    return _database.watchBudgets().map(
          (List<Budget> rows) => rows
              .map((Budget row) => CategoryBudget(
                    name: row.name,
                    type: row.type,
                    amount: row.amount,
                  ))
              .toList(),
        );
  }

  @override
  Future<void> setBudget({
    required String name,
    required String type,
    required double amount,
  }) {
    return _database.setBudget(name: name, type: type, amount: amount);
  }

  @override
  Future<void> clearBudget({required String name, required String type}) {
    return _database.clearBudget(name: name, type: type);
  }

  @override
  Stream<List<RecurringTemplateEntity>> watchRecurringTemplates() {
    return _database.watchRecurringTemplatesWithNames().map(
          (List<RecurringTemplateWithNames> rows) => rows
              .map((RecurringTemplateWithNames row) => RecurringTemplateEntity(
                    id: row.template.id,
                    type: row.template.type,
                    amount: row.template.amount,
                    categoryId: row.template.categoryId,
                    subcategoryId: row.template.subcategoryId,
                    note: row.template.note,
                    dayOfMonth: row.template.dayOfMonth,
                    active: row.template.active,
                    categoryName: row.categoryName,
                    subcategoryName: row.subcategoryName,
                    lastGeneratedOn: row.template.lastGeneratedOn,
                  ))
              .toList(),
        );
  }

  @override
  Future<int> addRecurringTemplate(RecurringTemplateEntity template) {
    return _database.insertRecurringTemplate(RecurringTemplatesCompanion.insert(
      type: template.type,
      amount: template.amount,
      categoryId: template.categoryId,
      subcategoryId: Value(template.subcategoryId),
      note: Value(template.note),
      dayOfMonth: template.dayOfMonth,
      createdAt: DateTime.now(),
      lastGeneratedOn: Value(template.lastGeneratedOn),
    ));
  }

  @override
  Future<void> setRecurringTemplateActive(int id, bool active) {
    return _database.setRecurringTemplateActive(id, active);
  }

  @override
  Future<int> deleteRecurringTemplate(int id) {
    return _database.deleteRecurringTemplate(id);
  }

  @override
  Future<int> applyRecurringTemplates(DateTime now) {
    return _database.applyRecurringTemplates(now);
  }

  TransactionEntity _toEntity(TransactionWithNames row) {
    return TransactionEntity(
      id: row.transaction.id,
      type: row.transaction.type,
      amount: row.transaction.amount,
      categoryId: row.transaction.categoryId,
      subcategoryId: row.transaction.subcategoryId,
      categoryName: row.categoryName,
      subcategoryName: row.subcategoryName,
      note: row.transaction.note,
      date: row.transaction.date,
      createdAt: row.transaction.createdAt,
    );
  }
}

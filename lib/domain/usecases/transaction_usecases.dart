import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/entities/summary_result.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';

class GetTransactionsUseCase {
  final TransactionRepository _repository;

  GetTransactionsUseCase(this._repository);

  Future<List<TransactionEntity>> call() => _repository.getAllTransactions();
  Stream<List<TransactionEntity>> watch() => _repository.watchAllTransactions();
}

class GetTransactionsByDateRangeUseCase {
  final TransactionRepository _repository;

  GetTransactionsByDateRangeUseCase(this._repository);

  Future<List<TransactionEntity>> call(DateTime start, DateTime end) =>
      _repository.getTransactionsByDateRange(start, end);
}

class AddTransactionUseCase {
  final TransactionRepository _repository;

  AddTransactionUseCase(this._repository);

  Future<int> call(TransactionEntity transaction) => _repository.insertTransaction(transaction);
}

class UpdateTransactionUseCase {
  final TransactionRepository _repository;

  UpdateTransactionUseCase(this._repository);

  Future<bool> call(TransactionEntity transaction) => _repository.updateTransaction(transaction);
}

class DeleteTransactionUseCase {
  final TransactionRepository _repository;

  DeleteTransactionUseCase(this._repository);

  Future<int> call(int id) => _repository.deleteTransaction(id);
}

class GetSummaryUseCase {
  final TransactionRepository _repository;

  GetSummaryUseCase(this._repository);

  Future<SummaryResult> call({DateTime? start, DateTime? end}) async {
    final income = await _repository.getTotalIncome(start: start, end: end);
    final expense = await _repository.getTotalExpense(start: start, end: end);
    final expenseByCategory = await _repository.getExpenseByCategory(start: start, end: end);
    final incomeByCategory = await _repository.getIncomeByCategory(start: start, end: end);
    // The balance carries. Whatever was left at the end of the previous month is the
    // starting point of this one, so it is everything entered up to the end of the
    // month on screen rather than that month's own income minus its own expense — the
    // figure that used to restart at zero on the 1st. Income and expense above stay
    // monthly: they are what the month did, and only the balance is a running total.
    final double incomeToDate = await _repository.getTotalIncome(end: end);
    final double expenseToDate = await _repository.getTotalExpense(end: end);
    return SummaryResult(
      totalIncome: income,
      totalExpense: expense,
      balance: incomeToDate - expenseToDate,
      expenseByCategory: expenseByCategory,
      incomeByCategory: incomeByCategory,
    );
  }
}
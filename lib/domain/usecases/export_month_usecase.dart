import 'package:expense_tracker/domain/entities/month_range.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:intl/intl.dart';

/// A month of data rendered as a JSON document ready to be archived.
class MonthExport {
  MonthExport({
    required this.fileName,
    required this.json,
    required this.monthLabel,
    required this.transactionCount,
    required this.totalIncome,
    required this.totalExpense,
  });

  final String fileName;
  final Map<String, dynamic> json;
  final String monthLabel;
  final int transactionCount;
  final double totalIncome;
  final double totalExpense;
}

/// Collects every transaction of a month, plus its summary, into JSON.
class ExportMonthUseCase {
  ExportMonthUseCase(this._repository);

  final TransactionRepository _repository;

  static final DateFormat _fileStamp = DateFormat('yyyy-MM');
  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');
  static final DateFormat _monthLabel = DateFormat('MMMM yyyy');
  static final DateFormat _timestamp = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

  /// Every month this database has a transaction in, oldest first.
  ///
  /// What "export everything" means: the months that hold something, not every
  /// month since the first one. The caller walks the list one month at a time so
  /// that it can say how far along it is, which is why this returns months rather
  /// than the exports themselves.
  Future<List<DateTime>> monthsWithTransactions() =>
      _repository.getMonthsWithTransactions();

  Future<MonthExport> call(DateTime month) async {
    // MonthRange owns the boundary reasoning, and the same range feeds the home
    // and statistics screens, so a backup can no longer disagree with the totals
    // those screens showed. Rows written before the add page normalised its date
    // still carry a time-of-day, which is why the bound is the last representable
    // instant rather than midnight of the following month.
    final MonthRange range = MonthRange.of(month);
    final DateTime start = range.start;
    final DateTime end = range.end;

    final List<TransactionEntity> transactions =
        await _repository.getTransactionsByDateRange(start, end);
    final Map<String, double> expenseByCategory =
        await _repository.getExpenseByCategory(start: start, end: end);
    final Map<String, double> incomeByCategory =
        await _repository.getIncomeByCategory(start: start, end: end);
    final double totalIncome =
        await _repository.getTotalIncome(start: start, end: end);
    final double totalExpense =
        await _repository.getTotalExpense(start: start, end: end);

    final List<TransactionEntity> ordered = <TransactionEntity>[
      ...transactions
    ]..sort(
        (TransactionEntity a, TransactionEntity b) => a.date.compareTo(b.date));

    final Map<String, dynamic> json = <String, dynamic>{
      'app': 'Expense Tracker',
      'schemaVersion': 1,
      'currency': 'IDR',
      'exportedAt': _timestamp.format(DateTime.now()),
      'period': <String, dynamic>{
        'year': range.year,
        'month': range.month,
        'startDate': _isoDate.format(range.start),
        'endDate': _isoDate.format(range.day(range.dayCount)),
      },
      'summary': <String, dynamic>{
        'totalIncome': totalIncome,
        'totalExpense': totalExpense,
        'balance': totalIncome - totalExpense,
        'incomeByCategory': _breakdown(incomeByCategory),
        'expenseByCategory': _breakdown(expenseByCategory),
      },
      'transactions': ordered
          .map(
            (TransactionEntity transaction) => <String, dynamic>{
              'id': transaction.id,
              'date': _isoDate.format(transaction.date),
              'type': transaction.type,
              'category': transaction.categoryName,
              'subcategory': transaction.subcategoryName,
              'amount': transaction.amount,
              'note': transaction.note,
            },
          )
          .toList(),
    };

    return MonthExport(
      fileName: 'expense-tracker-${_fileStamp.format(start)}.json',
      json: json,
      monthLabel: _monthLabel.format(start),
      transactionCount: ordered.length,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
    );
  }

  /// Turns a `{category: total}` map into a total-descending list.
  List<Map<String, dynamic>> _breakdown(Map<String, double> values) {
    final List<MapEntry<String, double>> entries = values.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));

    return entries
        .map((MapEntry<String, double> entry) => <String, dynamic>{
              'category': entry.key,
              'total': entry.value,
            })
        .toList();
  }
}

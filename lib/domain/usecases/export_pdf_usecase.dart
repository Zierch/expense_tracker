import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:intl/intl.dart';

/// The last instant of [day], in local time.
///
/// The database stores the moment a row was entered, not a bare calendar day, so
/// binding a range at midnight would drop every transaction of the final day.
/// One microsecond past the last second keeps that day inside the range without
/// spilling into the next one — the same bound `MonthRange` reasons about for a
/// whole month.
DateTime endOfDay(DateTime day) => DateTime(day.year, day.month, day.day + 1)
    .subtract(const Duration(microseconds: 1));

/// Everything one PDF report shows, gathered once so that drawing it stays a
/// pure function of the data.
class PdfReportData {
  PdfReportData({
    required this.from,
    required this.to,
    required this.transactions,
    required this.totalIncome,
    required this.totalExpense,
    required this.expenseByCategory,
    required this.incomeByCategory,
  });

  /// First day of the range, inclusive.
  final DateTime from;

  /// Last day of the range, inclusive.
  final DateTime to;

  /// Oldest first, so the report reads like a ledger rather than a feed.
  final List<TransactionEntity> transactions;

  final double totalIncome;
  final double totalExpense;

  /// `{category: total}`, biggest first.
  final List<MapEntry<String, double>> expenseByCategory;
  final List<MapEntry<String, double>> incomeByCategory;

  static final DateFormat _stamp = DateFormat('yyyy-MM-dd');

  double get balance => totalIncome - totalExpense;
  int get transactionCount => transactions.length;

  /// Named by its range, so two exports never overwrite each other and the name
  /// still says what is inside once it leaves the share sheet.
  String get fileName =>
      'expense-tracker-${_stamp.format(from)}_${_stamp.format(to)}.pdf';
}

/// Collects a date range into [PdfReportData] for the PDF renderer.
///
/// Deliberately not [ExportMonthUseCase]: that one is the Drive backup, shaped by
/// a schema and pinned to a month. This one answers a range the user picked, and
/// shares nothing with it but the queries.
class ExportPdfUseCase {
  ExportPdfUseCase(this._repository);

  final TransactionRepository _repository;

  Future<PdfReportData> call({
    required DateTime from,
    required DateTime to,
  }) async {
    final DateTime start = DateTime(from.year, from.month, from.day);
    final DateTime end = endOfDay(to);

    if (start.isAfter(end)) {
      throw ArgumentError('The range ends before it starts: $from..$to');
    }
    final List<TransactionEntity> transactions =
        await _repository.getTransactionsByDateRange(start, end);
    final double totalIncome =
        await _repository.getTotalIncome(start: start, end: end);
    final double totalExpense =
        await _repository.getTotalExpense(start: start, end: end);
    final Map<String, double> expenseByCategory =
        await _repository.getExpenseByCategory(start: start, end: end);
    final Map<String, double> incomeByCategory =
        await _repository.getIncomeByCategory(start: start, end: end);

    final List<TransactionEntity> ordered = <TransactionEntity>[...transactions]
      // `newestFirst` is a total order over the same fields the list uses, so
      // flipping its arguments reverses it without inventing a second rule.
      ..sort((TransactionEntity a, TransactionEntity b) => newestFirst(b, a));

    return PdfReportData(
      from: start,
      to: DateTime(to.year, to.month, to.day),
      transactions: ordered,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      expenseByCategory: _totalDescending(expenseByCategory),
      incomeByCategory: _totalDescending(incomeByCategory),
    );
  }

  List<MapEntry<String, double>> _totalDescending(Map<String, double> values) {
    final List<MapEntry<String, double>> entries = values.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));
    return entries;
  }
}

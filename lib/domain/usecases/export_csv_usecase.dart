import 'package:expense_tracker/data/services/csv_report_builder.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/usecases/export_pdf_usecase.dart'
    show endOfDay;
import 'package:intl/intl.dart';

/// A date range as a CSV file, ready to be written wherever the user chooses.
class CsvExport {
  CsvExport({
    required this.fileName,
    required this.text,
    required this.transactionCount,
  });

  final String fileName;

  /// The whole file, header row and byte-order mark included.
  final String text;

  final int transactionCount;
}

/// Collects a date range into CSV: one row per transaction, oldest first.
///
/// Deliberately not a second report. A CSV is data to be summed, sorted and
/// charted elsewhere, so it carries the transactions and nothing a spreadsheet
/// could work out from them — no totals, no breakdown, no layout.
///
/// The range is read exactly as the PDF reads it, including [endOfDay], so the
/// two exports of the same days cannot disagree about which rows are in them.
class ExportCsvUseCase {
  ExportCsvUseCase(this._repository);

  final TransactionRepository _repository;

  static final DateFormat _stamp = DateFormat('yyyy-MM-dd');

  Future<CsvExport> call({
    required DateTime from,
    required DateTime to,
  }) async {
    final DateTime start = DateTime(from.year, from.month, from.day);
    final DateTime end = endOfDay(to);

    if (start.isAfter(end)) {
      throw ArgumentError('The range ends before it starts: $from..$to');
    }

    final List<TransactionEntity> rows =
        await _repository.getTransactionsByDateRange(start, end);
    final List<TransactionEntity> ordered = <TransactionEntity>[...rows]
      // `newestFirst` is a total order over the same fields the list uses, so
      // flipping its arguments reverses it without inventing a second rule.
      ..sort((TransactionEntity a, TransactionEntity b) => newestFirst(b, a));

    return CsvExport(
      // Named by its range, like the PDF, so two exports never overwrite each
      // other and the name still says what is inside once it leaves the app.
      fileName: 'expense-tracker-${_stamp.format(start)}_'
          '${_stamp.format(to)}.csv',
      text: buildCsvReport(ordered),
      transactionCount: ordered.length,
    );
  }
}

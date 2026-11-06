import 'dart:convert';

import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:intl/intl.dart';

/// Complete database export across all months rendered as a JSON document.
class SnapshotExport {
  const SnapshotExport({
    required this.fileName,
    required this.json,
    required this.transactionCount,
    required this.totalIncome,
    required this.totalExpense,
    required this.monthsCount,
  });

  final String fileName;
  final Map<String, dynamic> json;
  final int transactionCount;
  final double totalIncome;
  final double totalExpense;
  final int monthsCount;

  String get jsonText => const JsonEncoder.withIndent('  ').convert(json);
}

/// Collects every transaction across all months, plus summary totals, into JSON.
class ExportSnapshotUseCase {
  ExportSnapshotUseCase(this._repository);

  final TransactionRepository _repository;

  static final DateFormat _fileStamp = DateFormat("yyyyMMdd'T'HHmmss");
  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');
  static final DateFormat _timestamp = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

  Future<SnapshotExport> call({DateTime? now}) async {
    final DateTime exportTime = now ?? DateTime.now();

    final List<TransactionEntity> transactions =
        await _repository.getAllTransactions();
    final List<DateTime> months =
        await _repository.getMonthsWithTransactions();
    final double totalIncome = await _repository.getTotalIncome();
    final double totalExpense = await _repository.getTotalExpense();
    final Map<String, double> incomeByCategory =
        await _repository.getIncomeByCategory();
    final Map<String, double> expenseByCategory =
        await _repository.getExpenseByCategory();

    final List<TransactionEntity> ordered = <TransactionEntity>[
      ...transactions,
    ]..sort((TransactionEntity a, TransactionEntity b) {
        final int dateCmp = a.date.compareTo(b.date);
        if (dateCmp != 0) return dateCmp;
        final int createdCmp = a.createdAt.compareTo(b.createdAt);
        if (createdCmp != 0) return createdCmp;
        return a.id.compareTo(b.id);
      });

    final String? startDate =
        ordered.isEmpty ? null : _isoDate.format(ordered.first.date);
    final String? endDate =
        ordered.isEmpty ? null : _isoDate.format(ordered.last.date);

    final Map<String, dynamic> json = <String, dynamic>{
      'app': 'Expense Tracker',
      'schemaVersion': 2,
      'backupType': 'snapshot',
      'currency': 'IDR',
      'exportedAt': _timestamp.format(exportTime),
      'period': <String, dynamic>{
        'type': 'all',
        'monthCount': months.length,
        'startDate': startDate,
        'endDate': endDate,
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

    return SnapshotExport(
      fileName:
          'expense-tracker-snapshot-${_fileStamp.format(exportTime)}.json',
      json: json,
      transactionCount: ordered.length,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      monthsCount: months.length,
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

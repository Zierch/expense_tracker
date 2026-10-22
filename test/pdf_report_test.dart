// The PDF report's logic is split in two: the use case decides what the report
// says, the builder decides how it looks. Only the use case needs a repository,
// so it is checked against the same in-memory fake the JSON export uses, and the
// builder is checked on a hand-built report.

import 'dart:convert';
import 'dart:typed_data';

import 'package:expense_tracker/data/services/pdf_report_builder.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/usecases/export_pdf_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('endOfDay', () {
    test('keeps the whole final day and nothing of the next', () {
      final DateTime end = endOfDay(DateTime(2026, 10, 22));

      expect(end.isAfter(DateTime(2026, 10, 22, 23, 59, 59)), isTrue);
      expect(end.isBefore(DateTime(2026, 10, 23)), isTrue);
      expect(end.year, 2026);
      expect(end.month, 10);
      expect(end.day, 22);
    });

    test('crosses a month boundary without a special case', () {
      final DateTime end = endOfDay(DateTime(2026, 2, 28));

      expect(DateTime(2026, 2, 28, 12).isBefore(end), isTrue);
      expect(DateTime(2026, 3, 1).isAfter(end), isTrue);
      expect(end.day, 28);
    });
  });

  group('ExportPdfUseCase', () {
    test('collects the range, oldest first, with sums per type', () async {
      final _FakeRepository repository = _FakeRepository(<TransactionEntity>[
        _row(id: 1, day: 2, type: 'income', category: 'Salary', amount: 900),
        _row(id: 2, day: 2, type: 'expense', category: 'Food', amount: 100),
        _row(id: 3, day: 5, type: 'expense', category: 'Food', amount: 50),
        _row(id: 4, day: 9, type: 'expense', category: 'Transport', amount: 25),
      ]);

      final PdfReportData data = await ExportPdfUseCase(repository)
          .call(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 9));

      expect(data.transactionCount, 4);
      expect(
        data.transactions.map((TransactionEntity t) => t.id),
        <int>[1, 2, 3, 4],
        reason: 'the report reads like a ledger, so the oldest row comes first',
      );
      expect(data.totalIncome, 900);
      expect(data.totalExpense, 175);
      expect(data.balance, 725);
      expect(
        data.expenseByCategory.map((MapEntry<String, double> e) => e.key),
        <String>['Food', 'Transport'],
        reason: 'biggest category first',
      );
      expect(data.expenseByCategory.first.value, 150);
    });

    test('a one-day range still includes that day\'s rows', () async {
      final _FakeRepository repository = _FakeRepository(<TransactionEntity>[
        _row(id: 1, day: 9, type: 'expense', category: 'Food', amount: 25),
      ]);

      final PdfReportData data = await ExportPdfUseCase(repository)
          .call(from: DateTime(2026, 10, 9), to: DateTime(2026, 10, 9));

      expect(data.transactionCount, 1);
      expect(data.fileName, 'expense-tracker-2026-10-09_2026-10-09.pdf');
    });

    test('a range that ends before it starts is rejected', () {
      expect(
        () => ExportPdfUseCase(_FakeRepository(<TransactionEntity>[]))
            .call(from: DateTime(2026, 10, 9), to: DateTime(2026, 10, 1)),
        throwsArgumentError,
      );
    });
  });

  group('buildPdfReport', () {
    test('draws a PDF with a summary, categories and every transaction',
        () async {
      final PdfReportData data = PdfReportData(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 9),
        transactions: <TransactionEntity>[
          _row(id: 1, day: 2, type: 'income', category: 'Salary', amount: 900),
          _row(id: 2, day: 2, type: 'expense', category: 'Food', amount: 100),
          _row(id: 3, day: 5, type: 'expense', category: 'Food', amount: 50),
        ],
        totalIncome: 900,
        totalExpense: 150,
        expenseByCategory: <MapEntry<String, double>>[
          const MapEntry<String, double>('Food', 150),
        ],
        incomeByCategory: <MapEntry<String, double>>[
          const MapEntry<String, double>('Salary', 900),
        ],
      );

      final Uint8List bytes = await buildPdfReport(data);

      expect(
        ascii.decode(bytes.sublist(0, 5)),
        '%PDF-',
        reason:
            'the share sheet needs a real PDF, not bytes that look like one',
      );
      expect(bytes.length, greaterThan(2000));
    });

    test('long ranges and long notes still produce a readable file', () async {
      final List<TransactionEntity> rows = <TransactionEntity>[
        for (int i = 1; i <= 120; i++)
          _row(
            id: i,
            day: (i % 28) + 1,
            type: i.isEven ? 'expense' : 'income',
            category: 'Category ${i % 7}',
            amount: i * 1000,
            note: 'A note long enough to wrap onto a second line in the table, '
                'repeated for row $i',
          ),
      ];

      final PdfReportData data = PdfReportData(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
        transactions: rows,
        totalIncome: 0,
        totalExpense: 0,
        expenseByCategory: const <MapEntry<String, double>>[],
        incomeByCategory: const <MapEntry<String, double>>[],
      );

      final Uint8List bytes = await buildPdfReport(data);

      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(
        bytes.length,
        greaterThan(4000),
        reason: 'a multi-page table has to actually overflow the first page',
      );
    });
  });
}

TransactionEntity _row({
  required int id,
  required int day,
  required String type,
  required String category,
  required double amount,
  String? note,
}) {
  final DateTime date = DateTime(2026, 10, day);
  return TransactionEntity(
    id: id,
    type: type,
    amount: amount,
    categoryId: 1,
    categoryName: category,
    note: note,
    date: date,
    createdAt: date,
  );
}

/// Minimal in-memory repository, mirroring the Drift queries the report needs.
class _FakeRepository implements TransactionRepository {
  _FakeRepository(this.transactions);

  final List<TransactionEntity> transactions;

  List<TransactionEntity> _inRange(DateTime? start, DateTime? end) {
    return transactions.where((TransactionEntity transaction) {
      if (start != null && transaction.date.isBefore(start)) return false;
      if (end != null && transaction.date.isAfter(end)) return false;
      return true;
    }).toList();
  }

  double _total(List<TransactionEntity> rows, String type) => rows
      .where((TransactionEntity t) => t.type == type)
      .fold<double>(0, (double sum, TransactionEntity t) => sum + t.amount);

  Map<String, double> _byCategory(List<TransactionEntity> rows, String type) {
    final Map<String, double> result = <String, double>{};
    for (final TransactionEntity t
        in rows.where((TransactionEntity row) => row.type == type)) {
      result[t.displayCategory] = (result[t.displayCategory] ?? 0) + t.amount;
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
      _total(_inRange(start, end), 'income');

  @override
  Future<double> getTotalExpense({DateTime? start, DateTime? end}) async =>
      _total(_inRange(start, end), 'expense');

  @override
  Future<Map<String, double>> getIncomeByCategory({
    DateTime? start,
    DateTime? end,
  }) async =>
      _byCategory(_inRange(start, end), 'income');

  @override
  Future<Map<String, double>> getExpenseByCategory({
    DateTime? start,
    DateTime? end,
  }) async =>
      _byCategory(_inRange(start, end), 'expense');

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
  Future<int> deleteTransaction(int id) async => 0;
}

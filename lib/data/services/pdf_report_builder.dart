import 'dart:typed_data';

import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/usecases/export_pdf_usecase.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Draws [PdfReportData] into a PDF file.
///
/// A plain function, not a stateful service: the use case decides *what* the
/// report says, this file only decides how it looks, so each can be checked
/// without the other.
///
/// The text is set in the PDF format's built-in Helvetica, which covers Latin-1
/// but not emoji or CJK — those characters are dropped silently by the renderer.
/// A bundled Unicode font would fix Latin-2/Cyrillic at the cost of half a
/// megabyte in the APK, and still not cover emoji or Chinese; add one only if
/// notes in those scripts become ordinary. Report copy itself stays ASCII so the
/// report's own labels never vanish.
Future<Uint8List> buildPdfReport(PdfReportData data) {
  final pw.Document document = pw.Document(
    title: 'Expense Tracker report',
    author: 'Expense Tracker',
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      // The default cap of 20 pages exists to catch a layout that never
      // finishes; a long range legitimately runs past it, and a year of entries
      // stays well inside 500.
      maxPages: 500,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      header: (pw.Context context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(
                'Expense Tracker - ${_rangeLabel(data)}',
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ),
      footer: (pw.Context context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ),
      // Each section is spread into this list rather than wrapped in a Column:
      // a table nested in a column cannot be split across a page break, so it is
      // pushed whole to the next page, and pushing it there forever is what the
      // renderer reports as a widget too big for any page.
      build: (pw.Context context) => <pw.Widget>[
        _heading(data),
        pw.SizedBox(height: 16),
        _summary(data),
        if (data.expenseByCategory.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 20),
          ..._categorySection(
            'Expenses by category',
            data.expenseByCategory,
            data.totalExpense,
            _expense,
          ),
        ],
        if (data.incomeByCategory.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 20),
          ..._categorySection(
            'Income by category',
            data.incomeByCategory,
            data.totalIncome,
            _income,
          ),
        ],
        pw.SizedBox(height: 20),
        ..._transactionSection(data),
      ],
    ),
  );

  return document.save();
}

// -----------------------------------------------------------------------------
// Section builders
// -----------------------------------------------------------------------------

pw.Widget _heading(PdfReportData data) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Text(
        'Expense Tracker',
        style: const pw.TextStyle(
          fontSize: 22,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        _rangeLabel(data),
        style: const pw.TextStyle(fontSize: 12, color: _teal),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        '${data.transactionCount} '
        '${data.transactionCount == 1 ? 'transaction' : 'transactions'}'
        ' - generated ${_day.format(DateTime.now())}',
        style: const pw.TextStyle(fontSize: 9, color: _muted),
      ),
    ],
  );
}

pw.Widget _summary(PdfReportData data) {
  return pw.Row(
    children: <pw.Widget>[
      _summaryBox('Income', data.totalIncome, _income),
      pw.SizedBox(width: 8),
      _summaryBox('Expense', data.totalExpense, _expense),
      pw.SizedBox(width: 8),
      _summaryBox('Balance', data.balance, _teal),
    ],
  );
}

pw.Widget _summaryBox(String label, double amount, PdfColor color) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: const pw.BoxDecoration(color: _tint),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _money(amount),
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

List<pw.Widget> _categorySection(
  String title,
  List<MapEntry<String, double>> rows,
  double total,
  PdfColor color,
) {
  return <pw.Widget>[
    _sectionTitle(title),
    pw.SizedBox(height: 6),
    pw.TableHelper.fromTextArray(
      headers: <String>['Category', 'Total'],
      data: <List<String>>[
        for (final MapEntry<String, double> row in rows)
          <String>[row.key, _money(row.value)],
        <String>['Total', _money(total)],
      ],
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _rule, width: 0.5),
      ),
      headerDecoration: const pw.BoxDecoration(color: _tint),
      headerStyle: const pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: _muted,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9, color: _ink),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      cellAlignments: <int, pw.AlignmentGeometry>{
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
      },
      columnWidths: <int, pw.TableColumnWidth>{
        1: const pw.FixedColumnWidth(90),
      },
      // The final row is the sum of the ones above it, so it is set apart
      // rather than read as just another category. Row numbers include the
      // header row, which is why the data's last index is `rows.length`.
      textStyleBuilder: (int column, dynamic value, int row) =>
          row == rows.length + 1
              ? pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: color,
                )
              : null,
    ),
  ];
}

List<pw.Widget> _transactionSection(PdfReportData data) {
  return <pw.Widget>[
    _sectionTitle('Transactions'),
    pw.SizedBox(height: 6),
    if (data.transactions.isEmpty)
      pw.Text(
        'No transactions in this range.',
        style: const pw.TextStyle(fontSize: 9, color: _muted),
      )
    else
      pw.TableHelper.fromTextArray(
        headers: <String>['Date', 'Category', 'Note', 'Amount'],
        data: <List<String>>[
          for (final TransactionEntity transaction in data.transactions)
            <String>[
              _day.format(transaction.date),
              _categoryLabel(transaction),
              transaction.note ?? '',
              '${transaction.isIncome ? '+' : '-'}'
                  '${_money(transaction.amount)}',
            ],
        ],
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _rule, width: 0.5),
        ),
        headerDecoration: const pw.BoxDecoration(color: _tint),
        headerStyle: const pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: _muted,
        ),
        cellStyle: const pw.TextStyle(fontSize: 9, color: _ink),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        cellAlignments: <int, pw.AlignmentGeometry>{
          0: pw.Alignment.centerLeft,
          3: pw.Alignment.centerRight,
        },
        columnWidths: <int, pw.TableColumnWidth>{
          0: const pw.FixedColumnWidth(68),
          3: const pw.FixedColumnWidth(88),
        },
        textStyleBuilder: (int column, dynamic value, int row) {
          if (column != 3 || row > data.transactions.length) return null;
          return pw.TextStyle(
            fontSize: 9,
            // Row numbers count the header row, so the transaction under a
            // row number is one earlier.
            color: data.transactions[row - 1].isIncome ? _income : _expense,
          );
        },
      ),
  ];
}

pw.Widget _sectionTitle(String title) => pw.Text(
      title,
      style: const pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
    );

// -----------------------------------------------------------------------------
// Text and colours
// -----------------------------------------------------------------------------

const PdfColor _ink = PdfColor.fromInt(0xFF1A1E22);
const PdfColor _muted = PdfColor.fromInt(0xFF5A646E);
const PdfColor _teal = PdfColor.fromInt(0xFF00897B);
const PdfColor _income = PdfColor.fromInt(0xFF2E9E5B);
const PdfColor _expense = PdfColor.fromInt(0xFFD64545);
const PdfColor _rule = PdfColor.fromInt(0xFFD9DEE3);
const PdfColor _tint = PdfColor.fromInt(0xFFF4F6F8);

final DateFormat _day = DateFormat('d MMM yyyy');
final NumberFormat _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

String _money(double amount) => _rupiah.format(amount);

/// A row's category with its subcategory when it has one.
///
/// The on-screen list shows whichever of the two is most specific, which reads
/// well next to a live filter but leaves a report full of rows named "Weekly".
String _categoryLabel(TransactionEntity transaction) {
  final String category = transaction.categoryName ?? '';
  final String subcategory = transaction.subcategoryName ?? '';
  if (category.isEmpty)
    return subcategory.isEmpty ? 'Uncategorized' : subcategory;
  return subcategory.isEmpty ? category : '$category - $subcategory';
}

String _rangeLabel(PdfReportData data) {
  if (data.from == data.to) return _day.format(data.from);
  return '${_day.format(data.from)} - ${_day.format(data.to)}';
}

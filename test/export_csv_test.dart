// The CSV export: a header, one row per transaction, and enough quoting to be
// read by a spreadsheet rather than by the app.
//
// The builder is a pure function, so most of this file needs no database and no
// widget: what a CSV has to get right is the text — fields that hold a comma, a
// quote or a line break, amounts that stay numbers, and text that a spreadsheet
// is not allowed to mistake for a formula. The use case adds the range and the
// file name, and is checked against a fake repository.

import 'package:expense_tracker/data/services/csv_report_builder.dart';
import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/usecases/export_csv_usecase.dart';
import 'package:expense_tracker/presentation/pages/backup_page.dart';
import 'package:expense_tracker/presentation/providers/backup_providers.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'sqlite_support.dart';
import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/services/file_picker_service.dart';
import 'package:expense_tracker/data/services/google_drive_service.dart'
    show BackupException;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionEntity _row({
  int id = 1,
  String type = 'expense',
  double amount = 250000,
  String? category = 'Expense',
  String? subcategory = 'Food',
  String? note,
  DateTime? date,
}) {
  final DateTime day = date ?? DateTime(2026, 10, 4);
  return TransactionEntity(
    id: id,
    type: type,
    amount: amount,
    categoryId: 1,
    subcategoryId: subcategory == null ? null : 2,
    categoryName: category,
    subcategoryName: subcategory,
    note: note,
    date: day,
    createdAt: day,
  );
}

/// The lines of a CSV, without the byte-order mark and without empty tails.
List<String> _lines(String csv) => csv.replaceFirst('\uFEFF', '').split('\r\n')
  ..removeWhere((String line) => line.isEmpty);

void main() {
  // One test drives a platform channel, which needs the test binding first.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('saveTextFile', () {
    const MethodChannel channel = MethodChannel('app.files');

    void answer(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    tearDown(() => answer((MethodCall call) async => null));

    test('hands Android the file name and the text it is to write', () async {
      MethodCall? seen;
      answer((MethodCall call) async {
        seen = call;
        return true;
      });

      expect(
        await FilePickerService()
            .saveTextFile(fileName: 'expense-tracker-2026-10.csv', text: 'a,b'),
        isTrue,
      );
      expect(seen!.method, 'saveTextFile');
      expect((seen!.arguments as Map<Object?, Object?>)['fileName'],
          'expense-tracker-2026-10.csv');
      expect((seen!.arguments as Map<Object?, Object?>)['text'], 'a,b');
    });

    test('backing out of the dialog is `false`, not a failure', () async {
      answer((MethodCall call) async => null);

      expect(
        await FilePickerService().saveTextFile(fileName: 'x.csv', text: ''),
        isFalse,
      );
    });

    test('a platform refusal arrives as something the card can show', () async {
      answer((MethodCall call) async {
        throw PlatformException(
            code: 'write_failed', message: 'No space left.');
      });

      expect(
        () => FilePickerService().saveTextFile(fileName: 'x.csv', text: 'a'),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('No space left.'),
        )),
      );
    });

    test('no channel at all is said plainly, not swallowed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      expect(
        () => FilePickerService().saveTextFile(fileName: 'x.csv', text: 'a'),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('not available on this device'),
        )),
      );
    });
  });

  group('buildCsvReport', () {
    test('starts with the mark a spreadsheet needs, then the header', () {
      final String csv = buildCsvReport(<TransactionEntity>[]);

      expect(csv.startsWith('\uFEFF'), isTrue,
          reason: 'Excel reads a UTF-8 CSV as the local code page without it');
      expect(_lines(csv).single, 'date,type,category,subcategory,amount,note');
    });

    test('writes one CRLF-terminated row per transaction', () {
      final String csv = buildCsvReport(<TransactionEntity>[
        _row(id: 1, date: DateTime(2026, 10, 4), note: 'Coffee'),
        _row(
          id: 2,
          date: DateTime(2026, 10, 9),
          type: 'income',
          category: 'Income',
          subcategory: 'Salary',
          amount: 4000000,
        ),
      ]);

      expect(_lines(csv), <String>[
        'date,type,category,subcategory,amount,note',
        '2026-10-04,expense,Expense,Food,250000,Coffee',
        '2026-10-09,income,Income,Salary,4000000,',
      ]);
    });

    test(
        'an amount stays a number: no trailing .0, no quotes, two decimals at '
        'most', () {
      expect(
          _lines(buildCsvReport(<TransactionEntity>[_row(amount: 1234.5)]))
              .last,
          '2026-10-04,expense,Expense,Food,1234.50,');
      expect(
          _lines(buildCsvReport(<TransactionEntity>[_row(amount: 7000)])).last,
          '2026-10-04,expense,Expense,Food,7000,');
      // A `double` artefact is rounded rather than written out in full.
      expect(
          _lines(buildCsvReport(<TransactionEntity>[_row(amount: 0.1 + 0.2)]))
              .last,
          '2026-10-04,expense,Expense,Food,0.30,');
    });

    test('quotes a field that holds a comma, and doubles a quote', () {
      final String csv = buildCsvReport(<TransactionEntity>[
        _row(note: 'Lunch, then a "coffee"'),
      ]);

      expect(_lines(csv).last, endsWith(',"Lunch, then a ""coffee"""'));
    });

    test('a missing subcategory or note is an empty field, not the word null',
        () {
      final String csv = buildCsvReport(<TransactionEntity>[
        _row(subcategory: null, note: null, category: null),
      ]);

      expect(_lines(csv).last, '2026-10-04,expense,,,250000,');
      expect(csv, isNot(contains('null')));
    });

    test(
        'text a spreadsheet would evaluate is defused, whatever it starts with',
        () {
      // A backup can carry a note this app never typed; importing one and then
      // exporting a CSV must not hand a spreadsheet something to run. Every
      // character that can begin a formula is checked, not just the obvious one.
      for (final String start in <String>['=', '+', '-', '@']) {
        final String csv = buildCsvReport(<TransactionEntity>[
          _row(note: '${start}HYPERLINK("http://example.invalid")'),
        ]);

        expect(_lines(csv).last, contains("'$start"),
            reason: 'a note starting with ${start.codeUnitAt(0)} stays text');
      }
    });

    test('a formula hidden behind leading whitespace is defused too', () {
      // The note is stored as typed, untrimmed, so a pasted ` =...` reaches this
      // builder verbatim — and a spreadsheet that trims a cell on import would
      // evaluate what followed the space. The apostrophe therefore goes in front
      // of the whitespace, which is what the 'normal' note below pins.
      for (final String lead in <String>[' ', '  ', '\t', '\r']) {
        final String csv = buildCsvReport(<TransactionEntity>[
          _row(note: '$lead=HYPERLINK("http://example.invalid")'),
        ]);

        expect(_lines(csv).last, contains("'$lead="),
            reason: 'the space before the formula does not hide it');
      }

      expect(
          _lines(buildCsvReport(<TransactionEntity>[_row(note: ' two')])).last,
          endsWith(', two'),
          reason: 'a space before ordinary text is left alone');
    });

    test('a line break inside a note is quoted, not a new row', () {
      final String csv = buildCsvReport(<TransactionEntity>[
        _row(note: 'two\nlines'),
      ]);

      expect(csv.contains('"two\nlines"'), isTrue);
      // Header plus one row: the note's own break did not start another.
      expect(
          csv.split('\r\n').where((String line) => line.isNotEmpty).length, 2);
    });
  });

  group('ExportCsvUseCase', () {
    test('names the file after the range and orders the rows oldest first',
        () async {
      final _FakeRepository repository = _FakeRepository(<TransactionEntity>[
        _row(id: 2, date: DateTime(2026, 10, 9)),
        _row(id: 1, date: DateTime(2026, 10, 2)),
      ]);

      final CsvExport export = await ExportCsvUseCase(repository)
          .call(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));

      expect(export.fileName, 'expense-tracker-2026-10-01_2026-10-31.csv');
      expect(export.transactionCount, 2);
      expect(
          _lines(export.text)
              .skip(1)
              .map((String line) => line.split(',').first),
          <String>['2026-10-02', '2026-10-09']);
    });

    test('keeps the final day of the range, whatever time of day it carries',
        () async {
      final _FakeRepository repository = _FakeRepository(<TransactionEntity>[
        _row(id: 1, date: DateTime(2026, 10, 9, 23, 59, 59)),
      ]);

      final CsvExport export = await ExportCsvUseCase(repository)
          .call(from: DateTime(2026, 10, 9), to: DateTime(2026, 10, 9));

      expect(export.transactionCount, 1);
    });

    test('a range with nothing in it still names a file with just a header',
        () async {
      final CsvExport export =
          await ExportCsvUseCase(_FakeRepository(<TransactionEntity>[]))
              .call(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));

      expect(export.transactionCount, 0);
      expect(_lines(export.text),
          <String>['date,type,category,subcategory,amount,note']);
    });

    test('a range that ends before it starts is rejected', () {
      expect(
        () => ExportCsvUseCase(_FakeRepository(<TransactionEntity>[]))
            .call(from: DateTime(2026, 10, 9), to: DateTime(2026, 10, 1)),
        throwsArgumentError,
      );
    });
  });

  group('the Save CSV button', () {
    /// The report card as the page shows it when nobody is signed in, with one
    /// transaction in the range it opens on.
    Future<void> pumpPage(
      AppDatabase db,
      WidgetTester tester,
      Future<Object?> Function(MethodCall call) answer,
    ) async {
      const MethodChannel channel = MethodChannel('app.files');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, answer);
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      tester.view.physicalSize = const Size(1000, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          googleAccountProvider.overrideWith(
            (Ref ref) => Stream<GoogleSignInAccount?>.value(null),
          ),
        ],
        child: const MaterialApp(home: BackupPage()),
      ));
      // The page holds live streams; fixed pumps settle it without waiting for a
      // stream that never stops.
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> saveCsv(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Save CSV'));
      await tester.tap(find.text('Save CSV'));
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    sqliteWidgetTest('saves the range it shows, and says what it wrote',
        (AppDatabase db, WidgetTester tester) async {
      final DateTime today = DateTime.now();
      final int categoryId = (await db.getCategories(type: 'expense')).first.id;
      final Subcategory food = (await db.getSubcategories(categoryId))
          .firstWhere((Subcategory s) => s.name == 'Food');
      await db.insertTransaction(TransactionsCompanion.insert(
        type: 'expense',
        amount: 75000,
        categoryId: categoryId,
        subcategoryId: Value(food.id),
        note: const Value('Lunch'),
        date: DateTime(today.year, today.month, 2),
        createdAt: Value(DateTime(today.year, today.month, 2)),
      ));

      MethodCall? seen;
      await pumpPage(db, tester, (MethodCall call) async {
        seen = call;
        return true;
      });

      await saveCsv(tester);

      expect(seen!.method, 'saveTextFile');
      final Map<Object?, Object?> arguments =
          seen!.arguments as Map<Object?, Object?>;
      expect(arguments['fileName'], startsWith('expense-tracker-'));
      expect(arguments['fileName'], endsWith('.csv'));
      expect(arguments['text'],
          contains('date,type,category,subcategory,amount,note'));
      expect(arguments['text'], contains('75000,Lunch'));

      expect(find.textContaining('Saved expense-tracker-'), findsOneWidget);
      expect(find.textContaining('with 1 transaction'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    sqliteWidgetTest('backing out of the dialog says nothing at all',
        (AppDatabase db, WidgetTester tester) async {
      await pumpPage(db, tester, (MethodCall call) async => null);

      await saveCsv(tester);

      // Nothing was written, so there is nothing to report and nothing to
      // apologise for: no hint, no error.
      expect(find.textContaining('Saved'), findsNothing);
      expect(find.textContaining('Could not save'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}

/// Only the range query is walked here; the rest is the same in-memory fake the
/// JSON and PDF exports are checked against.
class _FakeRepository implements TransactionRepository {
  _FakeRepository(this.transactions);

  final List<TransactionEntity> transactions;

  @override
  Future<List<TransactionEntity>> getTransactionsByDateRange(
    DateTime start,
    DateTime end,
  ) async =>
      transactions
          .where((TransactionEntity t) =>
              !t.date.isBefore(start) && !t.date.isAfter(end))
          .toList();

  @override
  Future<List<DateTime>> getMonthsWithTransactions() async => <DateTime>[];

  // Paths this test does not walk: it reads one range and writes nothing.
  @override
  Future<ImportWriteResult> importTransactions(
          List<ImportTransaction> transactions) async =>
      const ImportWriteResult(imported: 0, duplicates: 0);

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

  @override
  Future<double> getTotalIncome({DateTime? start, DateTime? end}) async =>
      transactions
          .where((TransactionEntity t) => t.type == 'income')
          .fold<double>(0, (double sum, TransactionEntity t) => sum + t.amount);

  @override
  Future<double> getTotalExpense({DateTime? start, DateTime? end}) async =>
      transactions
          .where((TransactionEntity t) => t.type == 'expense')
          .fold<double>(0, (double sum, TransactionEntity t) => sum + t.amount);

  @override
  Future<Map<String, double>> getExpenseByCategory(
          {DateTime? start, DateTime? end}) async =>
      <String, double>{};

  @override
  Future<Map<String, double>> getIncomeByCategory(
          {DateTime? start, DateTime? end}) async =>
      <String, double>{};
}

// Importing a backup: the file is written by this app, and is still input.
//
// Everything here fails in a way a user would only notice later — a row missing
// from a month they thought they had restored, a second copy of everything after
// importing the same file twice, or a month that half-arrived and cannot be told
// apart from one that fully did. So the tests are about counts and about what
// survived, not about the shape of the code:
//
//  * A backup's rows come back, with the categories the file names made along the
//    way, because a fresh install has never seen a custom subcategory.
//  * Importing the same file twice writes nothing the second time. That is what
//    makes a restore safe to retry after a failure.
//  * Rows the file got wrong are counted, not guessed at, and the readable rows
//    around them still land.
//  * A file that is not a backup, or was written by a newer app, is refused with
//    a sentence the user can act on.
//  * The screen reaches both halves: the file chooser's answer and the picker
//    refusal, through the real service.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/transaction_repository_impl.dart';
import 'package:expense_tracker/data/services/file_picker_service.dart';
import 'package:expense_tracker/data/services/google_drive_service.dart'
    show BackupException;
import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/usecases/import_month_usecase.dart';
import 'package:expense_tracker/presentation/pages/backup_page.dart';
import 'package:expense_tracker/presentation/providers/backup_providers.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sqlite_support.dart';

/// A backup of October 2026, in the shape `ExportMonthUseCase` writes.
String _backup({required List<Map<String, dynamic>> transactions}) {
  return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
    'app': 'Expense Tracker',
    'schemaVersion': 1,
    'currency': 'IDR',
    'exportedAt': '2026-10-31T20:00:00',
    'period': <String, dynamic>{
      'year': 2026,
      'month': 10,
      'startDate': '2026-10-01',
      'endDate': '2026-10-31',
    },
    'summary': <String, dynamic>{
      'totalIncome': 0,
      'totalExpense': 0,
      'balance': 0
    },
    'transactions': transactions,
  });
}

Map<String, dynamic> _row({
  String date = '2026-10-04',
  String type = 'expense',
  String category = 'Expense',
  String? subcategory = 'Food',
  Object? amount = 250000,
  String? note,
}) {
  return <String, dynamic>{
    'id': 1,
    'date': date,
    'type': type,
    'category': category,
    'subcategory': subcategory,
    'amount': amount,
    'note': note,
  };
}

Future<int> _rowCount(AppDatabase db) async =>
    (await db.select(db.transactions).get()).length;

void main() {
  // The picker test drives a platform channel, which needs the test binding
  // before any test runs.
  TestWidgetsFlutterBinding.ensureInitialized();

  sqliteTest('a backup\'s rows come back, and the categories it names are made',
      (AppDatabase db) async {
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));

    final ImportResult result =
        await import(_backup(transactions: <Map<String, dynamic>>[
      _row(note: 'Coffee with the team', subcategory: 'Coffee'),
      _row(
          date: '2026-10-09',
          amount: 4000000,
          type: 'income',
          subcategory: 'Salary'),
    ]));

    expect(result.monthLabel, 'October 2026');
    expect(result.imported, 2);
    expect(result.duplicates, 0);
    expect(result.unreadable, 0);

    final List<Transaction> rows = await db.select(db.transactions).get();
    expect(rows, hasLength(2));
    expect(
      rows.map((Transaction t) =>
          '${t.type} ${t.amount} ${t.date.toIso8601String().substring(0, 10)}'),
      containsAll(<String>[
        'expense 250000.0 2026-10-04',
        'income 4000000.0 2026-10-09'
      ]),
    );

    // `Coffee` is not in the seeded subcategory list, so the import has to have
    // created it rather than filing the row under something else.
    final int expenseCategoryId =
        (await db.getCategories(type: 'expense')).first.id;
    final List<String> expenseSubcategories =
        (await db.getSubcategories(expenseCategoryId))
            .map((Subcategory s) => s.name)
            .toList();
    expect(expenseSubcategories, contains('Coffee'));
  });

  sqliteTest('importing the same file twice adds nothing the second time',
      (AppDatabase db) async {
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));
    final String backup = _backup(transactions: <Map<String, dynamic>>[
      _row(),
      _row(date: '2026-10-17', amount: 120000, note: 'Market'),
    ]);

    final ImportResult first = await import(backup);
    final ImportResult second = await import(backup);

    expect(first.imported, 2);
    expect(second.imported, 0);
    expect(second.duplicates, 2);
    expect(await _rowCount(db), 2);
  });

  sqliteTest(
      'a row the file got wrong is counted, and its neighbours still land',
      (AppDatabase db) async {
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));

    final ImportResult result =
        await import(_backup(transactions: <Map<String, dynamic>>[
      _row(),
      _row(amount: 'two hundred thousand'), // not a number
      _row(date: 'last Tuesday'), // not a date
      _row(type: 'transfer'), // neither income nor expense
      _row(amount: -5000), // a negative amount
      _row(category: ''), // no category to file it under
    ]));

    expect(result.imported, 1);
    expect(result.unreadable, 5);
    expect(result.total, 6);
    expect(await _rowCount(db), 1);
  });

  sqliteTest('a time of day in an old backup is dropped, not stored',
      (AppDatabase db) async {
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));

    await import(_backup(transactions: <Map<String, dynamic>>[
      _row(date: '2026-10-04T18:30:00.000'),
    ]));

    final Transaction row = (await db.select(db.transactions).get()).single;
    expect(row.date, DateTime(2026, 10, 4));
  });

  sqliteTest(
      'a row stored with a time of day is still recognised as a duplicate',
      (AppDatabase db) async {
    // Rows written by older versions of the app carry the time they were entered
    // at, while an import always normalises to midnight. Matching the instant
    // exactly would miss this row and write a second copy of it — the money
    // counted twice — so the day, not the instant, is what is compared.
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));

    final int categoryId = (await db.getCategories(type: 'expense')).first.id;
    final Subcategory food = (await db.getSubcategories(categoryId))
        .firstWhere((Subcategory s) => s.name == 'Food');
    await db.insertTransaction(TransactionsCompanion.insert(
      type: 'expense',
      amount: 250000,
      categoryId: categoryId,
      subcategoryId: Value(food.id),
      note: const Value('Coffee with the team'),
      date: DateTime(2026, 10, 4, 18, 30),
      createdAt: Value(DateTime(2026, 10, 4, 18, 30)),
    ));

    final ImportResult result =
        await import(_backup(transactions: <Map<String, dynamic>>[
      _row(note: 'Coffee with the team'),
    ]));

    expect(result.imported, 0);
    expect(result.duplicates, 1);
    expect(await _rowCount(db), 1);
  });

  sqliteTest('a row is only a duplicate inside its own month',
      (AppDatabase db) async {
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));

    final ImportResult october =
        await import(_backup(transactions: <Map<String, dynamic>>[
      _row(),
    ]));
    final ImportResult september = await import(jsonEncode(<String, dynamic>{
      'app': 'Expense Tracker',
      'schemaVersion': 1,
      'period': <String, dynamic>{'year': 2026, 'month': 9},
      'transactions': <Map<String, dynamic>>[_row(date: '2026-09-04')],
    }));

    expect(october.imported, 1);
    expect(september.imported, 1);
    expect(september.duplicates, 0);
    expect(await _rowCount(db), 2);
  });

  sqliteTest('a file that is not a backup is refused with something to read',
      (AppDatabase db) async {
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));

    expect(
      () => import('{"hello": "world"}'),
      throwsA(isA<ImportException>().having(
        (ImportException e) => e.message,
        'message',
        contains('does not look like an Expense Tracker backup'),
      )),
    );

    expect(
      () => import('not json at all'),
      throwsA(isA<ImportException>().having(
        (ImportException e) => e.message,
        'message',
        contains('not readable as JSON'),
      )),
    );

    expect(
      () => import('{"app": "Some Other App", "transactions": []}'),
      throwsA(isA<ImportException>().having(
        (ImportException e) => e.message,
        'message',
        contains('Some Other App'),
      )),
    );

    expect(await _rowCount(db), 0);
  });

  sqliteTest('a backup of more rows than a month can hold is refused',
      (AppDatabase db) async {
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));

    final List<Map<String, dynamic>> tooMany =
        List<Map<String, dynamic>>.generate(
      ImportMonthUseCase.maxTransactions + 1,
      (int index) => _row(date: '2026-10-04', note: 'row $index'),
    );

    expect(
      () => import(_backup(transactions: tooMany)),
      throwsA(isA<ImportException>().having(
        (ImportException e) => e.message,
        'message',
        contains('more than this app will import at once'),
      )),
    );
    expect(await _rowCount(db), 0);
  });

  sqliteTest('a backup from a newer app is refused rather than half-read',
      (AppDatabase db) async {
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));
    final Map<String, dynamic> newer =
        jsonDecode(_backup(transactions: <Map<String, dynamic>>[_row()]))
            as Map<String, dynamic>;
    newer['schemaVersion'] = 2;

    expect(
      () => import(jsonEncode(newer)),
      throwsA(isA<ImportException>().having(
        (ImportException e) => e.message,
        'message',
        contains('newer version of the app'),
      )),
    );

    // `2.0` is a newer format too: reading it as old because of the dot would be
    // the one mistake this check exists to prevent.
    newer['schemaVersion'] = 2.0;
    expect(() => import(jsonEncode(newer)), throwsA(isA<ImportException>()));

    expect(await _rowCount(db), 0);
  });

  sqliteTest(
      'an amount too large to be a transaction, and a name that lies, are refused',
      (AppDatabase db) async {
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));

    final ImportResult result =
        await import(_backup(transactions: <Map<String, dynamic>>[
      _row(amount: 1e300), // a total of Infinity, and a balance of NaN
      _row(subcategory: 'Food\u202Eevil'), // a right-to-left override in a name
      _row(note: 'two\nlines'), // a newline where a name is drawn
    ]));

    expect(result.imported, 0);
    expect(result.unreadable, 3);
    expect(await _rowCount(db), 0);

    // A field that is simply absent is not a broken field: most transactions
    // have no note, and the export writes `null` for them.
    final ImportResult plain =
        await import(_backup(transactions: <Map<String, dynamic>>[
      _row(subcategory: null, note: null),
    ]));
    expect(plain.imported, 1);
    expect(plain.unreadable, 0);
  });

  sqliteTest('a transaction written by hand is not mistaken for a duplicate',
      (AppDatabase db) async {
    final ImportMonthUseCase import =
        ImportMonthUseCase(TransactionRepositoryImpl(db));

    // The same day and the same amount, but a different note: two coffees on one
    // day are two transactions, and only the exact row is a duplicate.
    final int categoryId = (await db.getCategories(type: 'expense')).first.id;
    final Subcategory food = (await db.getSubcategories(categoryId))
        .firstWhere((Subcategory s) => s.name == 'Food');
    await db.insertTransaction(TransactionsCompanion.insert(
      type: 'expense',
      amount: 250000,
      categoryId: categoryId,
      subcategoryId: Value(food.id),
      note: const Value('Second coffee'),
      date: DateTime(2026, 10, 4),
      createdAt: Value(DateTime(2026, 10, 4)),
    ));

    final ImportResult result =
        await import(_backup(transactions: <Map<String, dynamic>>[
      _row(note: 'Coffee with the team'),
    ]));

    expect(result.imported, 1);
    expect(result.duplicates, 0);
    expect(await _rowCount(db), 2);
  });

  sqliteWidgetTest('the card imports the file the chooser hands back',
      (AppDatabase db, WidgetTester tester) async {
    const MethodChannel channel = MethodChannel('app.files');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return _backup(transactions: <Map<String, dynamic>>[
        _row(note: 'Coffee with the team')
      ]);
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        googleAccountProvider.overrideWith(
          (Ref ref) => Stream<GoogleSignInAccount?>.value(null),
        ),
        importMonthUseCaseProvider.overrideWithValue(
          ImportMonthUseCase(TransactionRepositoryImpl(db)),
        ),
      ],
      child: const MaterialApp(home: BackupPage()),
    ));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Import a backup'), findsOneWidget);

    await tester.tap(find.text('Choose a backup file'));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Imported 1 transaction from October 2026'),
        findsOneWidget);
    expect(await _rowCount(db), 1);

    // The screen holds live streams; taking it down first is what keeps the
    // harness from closing the database underneath them.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  test('the file picker answers with the file, and refuses in words', () async {
    // The real service, driven through the channel Android would answer on.
    const MethodChannel channel = MethodChannel('app.files');
    final List<MethodCall> calls = <MethodCall>[];

    void answer(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    addTearDown(() => answer((MethodCall call) async => null));

    answer((MethodCall call) async {
      calls.add(call);
      return _backup(transactions: <Map<String, dynamic>>[_row()]);
    });

    expect(await FilePickerService().pickJsonText(),
        contains('"Expense Tracker"'));
    expect(calls.single.method, 'pickJsonFile');

    // Backed out of the chooser: `null`, which the card reads as "nothing
    // chosen" rather than as a failure.
    answer((MethodCall call) async => null);
    expect(await FilePickerService().pickJsonText(), isNull);

    // The platform refusing, in its own words — the size cap speaks this way.
    answer((MethodCall call) async {
      throw PlatformException(
          code: 'read_failed', message: 'That file is larger than 10 MB.');
    });
    expect(
      () => FilePickerService().pickJsonText(),
      throwsA(isA<BackupException>().having(
        (BackupException e) => e.message,
        'message',
        contains('larger than 10 MB'),
      )),
    );

    // No channel at all — a host test, or another platform.
    answer((MethodCall call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(
      () => FilePickerService().pickJsonText(),
      throwsA(isA<BackupException>().having(
        (BackupException e) => e.message,
        'message',
        contains('not available on this device'),
      )),
    );
  });
}

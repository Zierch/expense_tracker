// The amount field: digits in, grouped text out.
//
// Grouping is what makes "400000" readable while it is being typed — the count
// of zeros is the thing the eye cannot do — and it has to survive the two ways
// the value is written: typing, and the digit shortcut buttons. What the field
// ends up holding is also what the database must not receive, so the last test
// here goes all the way to a row.

import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/presentation/pages/add_transaction_page.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/widgets/idr_amount_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'sqlite_support.dart';

void main() {
  group('formatIdrDigits', () {
    test('groups every three digits with a dot', () {
      expect(formatIdrDigits('400000'), '400.000');
      expect(formatIdrDigits('1000'), '1.000');
      expect(formatIdrDigits('999999999999'), '999.999.999.999');
    });

    test('leaves a number of three digits or fewer alone', () {
      expect(formatIdrDigits('400'), '400');
      expect(formatIdrDigits('0'), '0');
      expect(formatIdrDigits(''), '');
    });

    test('collapses leading zeros rather than grouping them', () {
      expect(formatIdrDigits('000400000'), '400.000');
      expect(formatIdrDigits('000'), '0');
    });

    test('refuses a number past the ceiling, and takes the one below it', () {
      expect(formatIdrDigits('999999999999'), isNotNull);
      expect(formatIdrDigits('1000000000000'), isNull);
    });
  });

  group('parseIdrAmount', () {
    test('reads a grouped amount back as the number it stands for', () {
      expect(parseIdrAmount('400.000'), 400000);
      expect(parseIdrAmount('999.999.999.999'), 999999999999);
    });

    test('is null when there is no digit to read', () {
      expect(parseIdrAmount(''), isNull);
      expect(parseIdrAmount('Rp. '), isNull);
    });
  });

  test('formatIdrAmount shows a stored amount the way it is typed', () {
    expect(formatIdrAmount(400000), '400.000');
    expect(formatIdrAmount(0), '0');
  });

  group('IdrAmountInputFormatter', () {
    final IdrAmountInputFormatter formatter = IdrAmountInputFormatter();

    TextEditingValue edit(String from, String to, {int caret = -1}) {
      return formatter.formatEditUpdate(
        TextEditingValue(text: from),
        TextEditingValue(
          text: to,
          selection: TextSelection.collapsed(
            offset: caret < 0 ? to.length : caret,
          ),
        ),
      );
    }

    test('groups as the digits arrive', () {
      expect(edit('40000', '400000').text, '400.000');
      expect(edit('', '5').text, '5');
      expect(edit('5', '50').text, '50');
    });

    test('keeps the caret on the digit it was behind', () {
      // "1.00|0" loses its middle zero and becomes "100": the caret has to end
      // up after the two digits it was behind, not at its old offset.
      final TextEditingValue result = edit('1.000', '1.00', caret: 3);

      expect(result.text, '100');
      expect(result.selection.baseOffset, 2,
          reason: 'rebuilding the text without moving the caret leaves the '
              'next digit going in at the wrong place');
    });

    test('holds the ceiling rather than cutting the number down', () {
      final TextEditingValue result = edit('999.999.999.999', '999.999.999.9999');

      expect(result.text, '999.999.999.999');
    });

    test('drops anything that is not a digit', () {
      expect(edit('', 'Rp. 4a0b0').text, '400');
      expect(edit('1.000', '1.000,-').text, '1.000');
    });

    test('an emptied field stays empty', () {
      expect(edit('1', '').text, '');
    });
  });

  // ---------------------------------------------------------------------------
  // On the page
  // ---------------------------------------------------------------------------

  /// A window tall enough for the whole form to be built.
  ///
  /// A `ListView` only builds what is visible, so on the default test surface the
  /// button at the bottom of this form does not exist and cannot be tapped or
  /// inspected.
  void useTallWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpAddPage(WidgetTester tester, AppDatabase db) async {
    final GoRouter router = GoRouter(
      initialLocation: '/add',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/add', builder: (_, __) => const AddTransactionPage()),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  /// The field the amount goes into, found by its own label rather than by
  /// position in the form.
  Finder amountField() => find.ancestor(
        of: find.text('Amount'),
        matching: find.byType(TextFormField),
      );

  /// What the field holds, as opposed to what is drawn around it.
  String amountText(WidgetTester tester) {
    return tester
        .widget<TextField>(
          find.descendant(of: amountField(), matching: find.byType(TextField)),
        )
        .controller!
        .text;
  }

  sqliteWidgetTest(
    'the digits are grouped as they are typed',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);
      await pumpAddPage(tester, db);
      expect(amountField(), findsOneWidget);

      await tester.enterText(amountField(), '400000');
      await tester.pump();

      expect(amountText(tester), '400.000');
      expect(find.text('400.000'), findsWidgets,
          reason: 'the grouped number has to be on screen, not only in the '
              'controller');
    },
  );

  sqliteWidgetTest(
    'a shortcut button appends digits without breaking the grouping',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);
      await pumpAddPage(tester, db);

      await tester.enterText(amountField(), '400');
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, '000'));
      await tester.pump();

      expect(amountText(tester), '400.000');
    },
  );

  sqliteWidgetTest(
    'the grouped text is not what gets saved',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);
      await pumpAddPage(tester, db);

      await tester.enterText(amountField(), '400000');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final List<Transaction> rows = await db.select(db.transactions).get();
      expect(rows.single.amount, 400000,
          reason: 'the dots are for reading; a "400.000" written to the '
              'database would be a thousand times the amount that was typed');
    },
  );

  sqliteWidgetTest(
    'the ceiling holds, and the field says so by staying put',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);
      await pumpAddPage(tester, db);

      await tester.enterText(amountField(), '999999999999');
      await tester.pump();
      expect(amountText(tester), '999.999.999.999');

      await tester.tap(find.widgetWithText(OutlinedButton, '0'));
      await tester.pump();

      expect(amountText(tester), '999.999.999.999');
    },
  );
}
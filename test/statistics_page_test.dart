// The statistics page groups a month by week, and a week is not a month.
//
// It used to clip every week at the month edge, so a spend on September 30th belonged
// to no week of October at all: the month's own total did not count it (correct) and
// the weekly section lost it entirely, because the week it happened in was split in
// two and only the half inside October was shown. The weekly section now draws whole
// Monday–Sunday weeks and keeps the neighbouring days inside them.
//
// The month is handed in rather than read from the clock, so the fixtures can name a
// date years away from whenever this runs. The page's own default is still today.

import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/presentation/pages/statistics_page.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'sqlite_support.dart';

/// What the page renders for [amount]; the same formatter the cards use.
String _rupiah(double amount) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);

/// A row dated [date] of [type], using that type's first seeded category.
Future<int> _insert(
  AppDatabase db, {
  required double amount,
  required DateTime date,
  String type = 'expense',
}) async {
  final int categoryId = (await db.getCategories(type: type)).first.id;
  return db.insertTransaction(TransactionsCompanion.insert(
    type: type,
    amount: amount,
    categoryId: categoryId,
    date: date,
  ));
}

void main() {
  /// October 2026 begins on a Thursday, so its first week reaches back into September.
  final DateTime october = DateTime(2026, 10, 15);

  /// A window tall enough for the weekly card and its rows to be built.
  ///
  /// A `ListView` only builds what is visible, so on the default test surface a week
  /// row far enough down the page does not exist to be found.
  void useTallWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpStatistics(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: StatisticsPage(initialMonth: october)),
    ));
    await tester.pumpAndSettle();
  }

  /// The row of the bucket whose label is [label], so an amount can be read from the
  /// week it names rather than from anywhere on the page that happens to equal it.
  Finder weekRow(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;

  sqliteWidgetTest(
    'a week keeps the days it reaches into the months next door',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);

      // Tuesday of the week October 1st falls in, a day of the month itself, and the
      // Sunday of the week October 31st falls in.
      await _insert(db, amount: 5000, date: DateTime(2026, 9, 29));
      await _insert(db, amount: 20000, date: DateTime(2026, 10, 15));
      await _insert(db, amount: 7000, date: DateTime(2026, 11, 1));

      await pumpStatistics(tester, db);

      expect(
        find.descendant(
            of: find.byType(Card).first, matching: find.text(_rupiah(20000))),
        findsOneWidget,
        reason: 'the monthly total counts the month and nothing else',
      );
      expect(find.text(_rupiah(32000)), findsNothing,
          reason: 'the two neighbour days must not join the month total');

      expect(
        find.descendant(
            of: weekRow('Week 1  ·  28 Sep – 4 Oct'),
            matching: find.text(_rupiah(5000))),
        findsOneWidget,
        reason: 'the week that holds the 1st starts on the Monday before it, and '
            'keeps the September day it starts with',
      );
      expect(
        find.descendant(
            of: weekRow('Week 5  ·  26 Oct – 1 Nov'),
            matching: find.text(_rupiah(7000))),
        findsOneWidget,
        reason: 'and the closing week runs to its own Sunday, not to the 31st',
      );
    },
  );

  sqliteWidgetTest(
    'the month is picked from a list of months, not a calendar of days',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);
      await _insert(db, amount: 5000, date: DateTime(2026, 9, 29));
      await _insert(db, amount: 20000, date: DateTime(2026, 10, 15));

      await pumpStatistics(tester, db);

      expect(find.text('October 2026'), findsOneWidget,
          reason: 'the month on screen names itself');

      await tester.tap(find.text('October 2026'));
      await tester.pumpAndSettle();

      expect(find.text('Select month'), findsOneWidget,
          reason: 'the picker asks for a month, which is all the page filters by');

      await tester.tap(find.text('Sep'));
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsOneWidget,
          reason: 'one tap on a month is the whole step back');
      expect(
        find.descendant(
            of: find.byType(Card).first, matching: find.text(_rupiah(5000))),
        findsOneWidget,
        reason: 'and the page now describes September, where that expense lives',
      );
    },
  );

  sqliteWidgetTest(
    'switching period filter to week updates total and shows week detail',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);
      await _insert(db, amount: 5000, date: DateTime(2026, 9, 29));
      await _insert(db, amount: 20000, date: DateTime(2026, 10, 15));
      await _insert(db, amount: 7000, date: DateTime(2026, 11, 1));

      await pumpStatistics(tester, db);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      expect(find.text('Total Expense (Weekly)'), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(Card).first, matching: find.text(_rupiah(20000))),
        findsOneWidget,
        reason: 'only the mid-October expense is in the current week (12-18 Oct)',
      );
      expect(find.text('12 Oct – 18 Oct 2026'), findsOneWidget);
    },
  );

  sqliteWidgetTest(
    'switching period filter to year aggregates all transactions for that year',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);
      await _insert(db, amount: 5000, date: DateTime(2026, 9, 29));
      await _insert(db, amount: 20000, date: DateTime(2026, 10, 15));
      await _insert(db, amount: 7000, date: DateTime(2026, 11, 1));

      await pumpStatistics(tester, db);

      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();

      expect(find.text('Total Expense (Yearly)'), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(Card).first, matching: find.text(_rupiah(32000))),
        findsOneWidget,
        reason: 'all three expenses fall into year 2026',
      );
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('Monthly Summary'), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('November 2026'), findsOneWidget);
    },
  );

  sqliteWidgetTest(
    'switching to income tab updates total, shows weekly buckets and category breakdown',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);
      await _insert(db, amount: 5000, date: DateTime(2026, 9, 29), type: 'income');
      await _insert(db, amount: 20000, date: DateTime(2026, 10, 15), type: 'income');
      await _insert(db, amount: 7000, date: DateTime(2026, 11, 1), type: 'income');

      await pumpStatistics(tester, db);

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      expect(find.text('Total Income (Monthly)'), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(Card).first, matching: find.text(_rupiah(20000))),
        findsOneWidget,
        reason: 'monthly income total counts only October',
      );
      expect(
        find.descendant(
            of: weekRow('Week 1  ·  28 Sep – 4 Oct'),
            matching: find.text(_rupiah(5000))),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: weekRow('Week 5  ·  26 Oct – 1 Nov'),
            matching: find.text(_rupiah(7000))),
        findsOneWidget,
      );
      expect(find.text('Income by Category'), findsOneWidget);
    },
  );

  sqliteWidgetTest(
    'switching period filter to week and income tab shows week detail for income',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);
      await _insert(db, amount: 5000, date: DateTime(2026, 9, 29), type: 'income');
      await _insert(db, amount: 20000, date: DateTime(2026, 10, 15), type: 'income');
      await _insert(db, amount: 7000, date: DateTime(2026, 11, 1), type: 'income');

      await pumpStatistics(tester, db);

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      expect(find.text('Total Income (Weekly)'), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(Card).first, matching: find.text(_rupiah(20000))),
        findsOneWidget,
        reason: 'only mid-October income is in current week',
      );
      expect(find.text('12 Oct – 18 Oct 2026'), findsOneWidget);
      expect(find.text('Daily Detail'), findsOneWidget);
    },
  );

  sqliteWidgetTest(
    'switching period filter to year and income tab aggregates yearly income',
    (AppDatabase db, WidgetTester tester) async {
      useTallWindow(tester);
      await _insert(db, amount: 5000, date: DateTime(2026, 9, 29), type: 'income');
      await _insert(db, amount: 20000, date: DateTime(2026, 10, 15), type: 'income');
      await _insert(db, amount: 7000, date: DateTime(2026, 11, 1), type: 'income');

      await pumpStatistics(tester, db);

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();

      expect(find.text('Total Income (Yearly)'), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(Card).first, matching: find.text(_rupiah(32000))),
        findsOneWidget,
        reason: 'all three incomes fall into year 2026',
      );
      expect(find.text('Monthly Summary'), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('November 2026'), findsOneWidget);
    },
  );
}

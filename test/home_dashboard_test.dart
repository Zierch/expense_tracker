// The dashboard has to agree with the database, in three ways it did not.
//
// Each test here pins one broken agreement:
//
//  * A cancelled swipe lost its row from the screen. `TransactionTile` confirmed through
//    `onDismissed`, which fires only after `Dismissible` has already taken the tile out of
//    the list, so answering "Cancel" in the dialog had nothing left to put back. The row
//    returned on the next start of the app, which is what made it read as data loss.
//  * The totals card kept the numbers it was first built with. The rows arrive on a drift
//    stream while the totals come from four one-shot SQL queries, and nothing connected the
//    two, so adding or deleting a transaction moved the list and left income, expense and
//    balance stale until a pull-to-refresh.
//  * Same-day rows changed places between rebuilds. `date` is stored as a calendar day, so
//    a day's rows tie on it; the list query had no `ORDER BY`, and the screen re-sorted by
//    `date` alone with `List.sort`, which is not stable.
//
// The middle one is only observable from outside the screen — an insert the dashboard is
// never told about — and the third starts in SQL, so those are asserted at both levels.

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/transaction_repository_impl.dart';
import 'package:expense_tracker/presentation/pages/home_page.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/widgets/summary_card.dart';
import 'package:expense_tracker/presentation/widgets/transaction_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'sqlite_support.dart';

/// A row dated [date], with a creation time it can be told apart by.
Future<int> _insert(
  AppDatabase db, {
  required double amount,
  required DateTime date,
  DateTime? createdAt,
}) async {
  final int categoryId = (await db.getCategories(type: 'expense')).first.id;
  return db.insertTransaction(TransactionsCompanion.insert(
    type: 'expense',
    amount: amount,
    categoryId: categoryId,
    date: date,
    createdAt: Value(createdAt ?? date),
  ));
}

/// The dashboard with a real database behind it.
///
/// No router is needed: `HomePage` reaches for one from tap handlers, and nothing here
/// taps a row to navigate. The update controller is not stubbed because this is not the
/// root widget — `main.dart` is where the launch check is started, and it is not in play.
Future<void> _pumpHome(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: HomePage()),
  ));
}

/// Every piece of text the summary card is currently showing.
String _summaryText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(SummaryCard), matching: find.byType(Text)),
    )
    .map((Text text) => text.data ?? '')
    .join(' | ');

/// The amounts on the rows, in the order the rows are laid out.
List<String> _rowAmounts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(TransactionTile), matching: find.byType(Text)),
    )
    .map((Text text) => text.data ?? '')
    .where((String data) => data.startsWith('+') || data.startsWith('-'))
    .toList();

/// What the app renders for [amount]; the card and the rows both use this.
String _rupiah(double amount) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);

/// Swipes a row far enough to ask for the delete.
Future<void> _swipeToDelete(WidgetTester tester) async {
  await tester.drag(find.byType(Dismissible).first, const Offset(-600, 0));
  await tester.pumpAndSettle();
}

void main() {
  // The clock is only needed to keep rows inside the month on screen, so these tests read
  // it rather than pinning a date: a pinned date is outside the current month most of the
  // time, which would empty the list and test the empty state instead.
  final DateTime today = DateTime.now();
  final DateTime noon = DateTime(today.year, today.month, today.day, 12);

  sqliteTest('the list query returns newest first, ties repeatably', (AppDatabase db) async {
    // Fixed dates, years away from the clock, so nothing here depends on when this runs.
    final int olderDay = await _insert(db, amount: 1000,
        date: DateTime(2026, 3, 10), createdAt: DateTime(2026, 3, 10, 8));
    final int firstOfDay = await _insert(db, amount: 2000,
        date: DateTime(2026, 3, 12), createdAt: DateTime(2026, 3, 12, 9));
    final int laterThatDay = await _insert(db, amount: 3000,
        date: DateTime(2026, 3, 12), createdAt: DateTime(2026, 3, 12, 10));
    // Same day and same creation time as the row above: only the id can separate them,
    // and a second is the ordinary case for two entries typed one after another.
    final int sameSecond = await _insert(db, amount: 4000,
        date: DateTime(2026, 3, 12), createdAt: DateTime(2026, 3, 12, 10));

    final List<int> expected = <int>[sameSecond, laterThatDay, firstOfDay, olderDay];

    final rows = await db.getTransactionsWithJoinedNames();
    expect(rows.map((TransactionWithNames row) => row.transaction.id).toList(), expected,
        reason: 'the query behind the list has to order, not leave it to SQLite');

    final streamed = await TransactionRepositoryImpl(db).getAllTransactions();
    expect(streamed.map((t) => t.id).toList(), expected,
        reason: 'and the stream the dashboard subscribes to has to agree with it');
  });

  sqliteWidgetTest(
    'cancelling the delete leaves the row on screen',
    (AppDatabase db, WidgetTester tester) async {
      await _insert(db, amount: 10000, date: today);

      await _pumpHome(tester, db);
      await tester.pumpAndSettle();
      expect(find.byType(TransactionTile), findsOneWidget,
          reason: 'the swipe below needs a row, or it would pass against an empty list');

      await _swipeToDelete(tester);
      expect(find.text('Cancel'), findsOneWidget,
          reason: 'the swipe has to reach the confirmation dialog, or the assertion '
              'below would be about a gesture that never asked anything');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(TransactionTile), findsOneWidget,
          reason: 'a cancelled delete must leave the row where it was: it used to stay '
              'gone until the app was restarted');
      expect(await db.getAllTransactions(), hasLength(1),
          reason: 'and it must not have reached the database');
    },
  );

  sqliteWidgetTest(
    'confirming the delete drops the row',
    (AppDatabase db, WidgetTester tester) async {
      await _insert(db, amount: 10000, date: today);

      await _pumpHome(tester, db);
      await tester.pumpAndSettle();

      await _swipeToDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(TransactionTile), findsNothing,
          reason: 'the row stream has to be the thing that removes it, and it has to '
              'remove it without a pull-to-refresh');
      expect(await db.getAllTransactions(), isEmpty);
    },
  );

  sqliteWidgetTest(
    'the totals follow a write, with no pull',
    (AppDatabase db, WidgetTester tester) async {
      await _insert(db, amount: 10000, date: today);

      await _pumpHome(tester, db);
      await tester.pumpAndSettle();

      final String before = _summaryText(tester);
      expect(before, contains(_rupiah(10000)),
          reason: 'the card has to be showing the month before the write below means '
              'anything');

      // A write from outside the screen, which is exactly what the add page makes: no
      // pull, no invalidate, nothing the dashboard is told about.
      await _insert(db, amount: 25000, date: today);
      await tester.pumpAndSettle();

      final String after = _summaryText(tester);
      expect(after, isNot(before),
          reason: 'the card used to hold its first numbers until a manual refresh');
      expect(after, contains(_rupiah(35000)),
          reason: 'expense has to be the new total, not the one the card started with');
      expect(after, contains(_rupiah(-35000)),
          reason: 'the balance is derived from the two totals, so it has to move too');
    },
  );

  sqliteWidgetTest(
    'same-day rows hold their order on screen',
    (AppDatabase db, WidgetTester tester) async {
      // One day, three rows, and the insertion order deliberately not the display order:
      // all three tie on `date`, so anything that shows them as inserted is not ordering.
      await _insert(db, amount: 1000, date: today, createdAt: noon);
      await _insert(db, amount: 2000, date: today, createdAt: noon.add(const Duration(minutes: 5)));
      await _insert(db, amount: 3000, date: today, createdAt: noon.add(const Duration(minutes: 10)));

      await _pumpHome(tester, db);
      await tester.pumpAndSettle();

      expect(
        _rowAmounts(tester),
        <String>['-${_rupiah(3000)}', '-${_rupiah(2000)}', '-${_rupiah(1000)}'],
        reason: 'the newest entry of the day belongs at the top, and the same order has '
            'to survive every rebuild',
      );
    },
  );

  sqliteWidgetTest(
    'the last row clears the button that adds the next one',
    (AppDatabase db, WidgetTester tester) async {
      // Longer than the screen: the FAB only covers a row when the list reaches the
      // bottom, which is the moment the user is looking at what they last typed.
      for (int i = 1; i <= 15; i++) {
        await _insert(db, amount: 1000.0 * i, date: today,
            createdAt: noon.add(Duration(minutes: i)));
      }

      await _pumpHome(tester, db);
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      final Rect fab = tester.getRect(find.byType(FloatingActionButton));
      final double lastRowBottom =
          tester.getRect(find.byType(TransactionTile).last).bottom;

      expect(lastRowBottom, lessThanOrEqualTo(fab.top),
          reason: 'at the end of the list the last row sat underneath the extended FAB, '
              'so the newest entry was the one hidden');
    },
  );
}
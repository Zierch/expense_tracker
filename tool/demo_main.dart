// A throwaway dataset for the screenshots, so that no real phone has to be
// photographed to get one.
//
//     flutter run --profile -t tool/demo_main.dart
//
// Runs before the real `main()`, into the same database the app opens, and does
// nothing at all if that database already holds transactions — a second launch
// keeps the data instead of stacking a second copy on top of it. This file is a
// tool, not part of the app: `lib/main.dart` is the entrypoint the APK is built
// from, and nothing here is reachable from it.
//
// The numbers are invented. The month, however, is not: the dashboard opens on
// the current month, so the rows have to sit in it to be visible.

import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/main.dart' as app;
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppDatabase db = AppDatabase();
  try {
    if ((await db.getAllTransactions()).isEmpty) await _seed(db);
  } finally {
    await db.close();
  }

  await app.main();
}

/// The rows are named by their subcategory — the tile shows
/// `subcategoryName ?? categoryName`, while the statistics and the PDF break down
/// by the category above it — so this seeds against the categories the app itself
/// creates, not a set of its own.
///
/// It used to invent `Housing`, `Groceries`, `Transport` and friends. That read
/// fine in a screenshot, but it also meant the pie chart's colour table, which
/// knows the shipped names, fell through to its grey default for every slice: the
/// picture showed a chart no install could produce.
const List<(String, String)> _daily = <(String, String)>[
  ('Food', 'Lunch at the office'),
  ('Food', 'Groceries for the week'),
  ('Coffee Shop', 'Coffee with the team'),
  ('Fuel', 'Filled the tank'),
  ('Other Needs', 'Household bits'),
  ('Data/Internet Package', 'Monthly data plan'),
];

/// The larger rows of a month: what a household actually spends in one go.
const List<(String, String, double)> _monthly = <(String, String, double)>[
  ('Other Needs', 'Rent', 3200000),
  ('Data/Internet Package', 'Internet and data', 385000),
  ('Other Needs', 'Electricity bill', 320000),
  ('Coffee Shop', 'Coffee beans', 145000),
];

Future<void> _seed(AppDatabase db) async {
  /// Subcategory name to its id, and to the category that owns it.
  final Map<String, int> subcategoryIds = <String, int>{};
  final Map<String, int> categoryOfSub = <String, int>{};

  for (final String type in <String>['expense', 'income']) {
    for (final Category category in await db.getCategories(type: type)) {
      for (final Subcategory child in await db.getSubcategories(category.id)) {
        subcategoryIds[child.name] = child.id;
        categoryOfSub[child.name] = category.id;
      }
    }
  }

  final Random random = Random(7);
  final DateTime now = DateTime.now();

  Future<void> row({
    required String subcategory,
    required String type,
    required double amount,
    required DateTime date,
    String? note,
  }) async {
    await db.insertTransaction(TransactionsCompanion.insert(
      type: type,
      amount: amount,
      categoryId: categoryOfSub[subcategory]!,
      subcategoryId: Value(subcategoryIds[subcategory]!),
      note: Value(note),
      date: date,
      createdAt: Value(date),
    ));
  }

  /// The same month one to three months back, keeping the day inside every
  /// month — and inside today: a row dated tomorrow would read as a mistake in
  /// the screenshot.
  DateTime day(int monthsBack, int onDay) => DateTime(
        now.year,
        now.month - monthsBack,
        monthsBack == 0 && onDay > now.day ? now.day : onDay,
      );

  for (int back = 2; back >= 0; back--) {
    await row(
        subcategory: 'Salary',
        type: 'income',
        amount: 12500000,
        date: day(back, 25),
        note: 'Monthly salary');

    // The same bills land on the same days every month, so the statistics page
    // has a previous month to compare against instead of a flat line.
    for (final (String subcategory, String note, double amount) entry
        in _monthly) {
      await row(
        subcategory: entry.$1,
        type: 'expense',
        amount: entry.$3,
        date: day(back, 2 + _monthly.indexOf(entry) * 3),
        note: entry.$2,
      );
    }

    if (back == 1) {
      await row(
          subcategory: 'Freelance',
          type: 'income',
          amount: 2750000,
          date: day(back, 18),
          note: 'Website build');
    }

    for (int i = 0; i < 9; i++) {
      final (String subcategory, String note) =
          _daily[random.nextInt(_daily.length)];
      await row(
        subcategory: subcategory,
        type: 'expense',
        amount: <double>[
          32000,
          48000,
          65000,
          89000,
          125000,
          180000,
          240000,
          310000,
          420000
        ][random.nextInt(9)],
        date: day(back, 3 + random.nextInt(24)),
        note: note,
      );
    }
  }
}

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

/// Categories with the subcategory names that end up on the rows: the tile
/// shows `subcategoryName ?? categoryName`, so a row is named by its subcategory
/// while the statistics and the PDF break down by the category above it.
const Map<String, (String, List<String>)> _catalogue =
    <String, (String, List<String>)>{
  'Housing': ('expense', <String>['Rent', 'Electricity']),
  'Groceries': ('expense', <String>['Supermarket', 'Market']),
  'Transport': ('expense', <String>['Fuel', 'Ride Hailing']),
  'Dining': ('expense', <String>['Coffee', 'Restaurant']),
  'Subscriptions': ('expense', <String>['Streaming', 'Music']),
  'Health': ('expense', <String>['Pharmacy']),
  'Salary': ('income', <String>['Monthly Salary']),
  'Freelance': ('income', <String>['Side Project']),
};

Future<void> _seed(AppDatabase db) async {
  final Map<String, int> subcategoryIds = <String, int>{};

  /// The category a subcategory belongs to, which every row has to carry.
  final Map<String, int> categoryOfSub = <String, int>{};

  for (final MapEntry<String, (String, List<String>)> entry
      in _catalogue.entries) {
    final int categoryId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: entry.key, type: entry.value.$1),
        );

    for (final String child in entry.value.$2) {
      subcategoryIds[child] = await db.into(db.subcategories).insert(
            SubcategoriesCompanion.insert(categoryId: categoryId, name: child),
          );
      categoryOfSub[child] = categoryId;
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

  /// Subcategory and note travel together. A note that contradicts the row it
  /// sits under — "Coffee" over "Fuel" — is the one thing that would make the
  /// data read as generated rather than lived.
  const List<(String, String)> daily = <(String, String)>[
    ('Supermarket', 'Weekly groceries'),
    ('Market', 'Fresh produce'),
    ('Fuel', 'Filled the tank'),
    ('Ride Hailing', 'Ride to the office'),
    ('Coffee', 'Coffee with the team'),
    ('Restaurant', 'Dinner out'),
    ('Pharmacy', 'Vitamins'),
  ];

  for (int back = 2; back >= 0; back--) {
    await row(
        subcategory: 'Monthly Salary',
        type: 'income',
        amount: 12500000,
        date: day(back, 25),
        note: 'Monthly salary');
    await row(
        subcategory: 'Rent',
        type: 'expense',
        amount: 3200000,
        date: day(back, 2),
        note: 'Rent');
    await row(
        subcategory: 'Electricity',
        type: 'expense',
        amount: 320000.0 + random.nextInt(90000),
        date: day(back, 5),
        note: 'Electricity bill');
    await row(
        subcategory: 'Streaming',
        type: 'expense',
        amount: 54000,
        date: day(back, 7),
        note: 'Streaming plan');
    await row(
        subcategory: 'Music',
        type: 'expense',
        amount: 54990,
        date: day(back, 7),
        note: 'Music plan');

    if (back == 1) {
      await row(
          subcategory: 'Side Project',
          type: 'income',
          amount: 2750000,
          date: day(back, 18),
          note: 'Website build');
    }

    for (int i = 0; i < 9; i++) {
      final (String subcategory, String note) =
          daily[random.nextInt(daily.length)];
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

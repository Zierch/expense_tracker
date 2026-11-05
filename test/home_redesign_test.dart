import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/presentation/pages/home_page.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sqlite_support.dart';

void main() {
  sqliteWidgetTest(
    'home dashboard renders mascots and redesigned balance and activity cards',
    (AppDatabase db, WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HomePage()),
      ));
      await tester.pumpAndSettle();

      // Verify HomeBalanceCard and HomeActivityCard exist
      expect(find.byType(HomeBalanceCard), findsOneWidget);
      expect(find.byType(HomeActivityCard), findsOneWidget);

      // Verify bundled mascots are present
      final Finder piggyFinder = find.byWidgetPredicate(
        (Widget widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/piggy_bank.png',
      );
      final Finder receiptFinder = find.byWidgetPredicate(
        (Widget widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/receipt_mascot.png',
      );
      expect(piggyFinder, findsOneWidget);
      expect(receiptFinder, findsOneWidget);

      // Verify redundant actions (Theme, Statistics, Backup icons) in app bar are removed
      expect(find.byIcon(Icons.brightness_4_outlined), findsNothing);
      expect(find.byIcon(Icons.analytics_outlined), findsNothing);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);

      // Verify Add action on activity card
      expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
      expect(find.text('Track your spending'), findsOneWidget);
    },
  );

  sqliteWidgetTest(
    'balance visibility toggle works on redesigned HomeBalanceCard',
    (AppDatabase db, WidgetTester tester) async {
      final int categoryId = (await db.getCategories(type: 'expense')).first.id;
      await db.insertTransaction(TransactionsCompanion.insert(
        type: 'expense',
        amount: 50000,
        categoryId: categoryId,
        date: DateTime.now(),
        createdAt: Value(DateTime.now()),
      ));

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HomePage()),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // Tap to hide balance
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Rp ••••••'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // Tap to show balance again
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Rp ••••••'), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    },
  );
}

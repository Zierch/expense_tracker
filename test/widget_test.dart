// Widget tests for the transaction row.
//
// The Flutter counter stub that used to live here referenced a `MyApp` class
// that no longer exists, so it never compiled. These tests exercise real app
// widgets and need no database.

import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/presentation/widgets/transaction_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionEntity _transaction({
  int id = 1,
  String type = 'expense',
  double amount = 100000,
  String? categoryName = 'Salary',
  String? subcategoryName,
  String? note,
}) {
  final DateTime date = DateTime(2026, 1, 15);

  return TransactionEntity(
    id: id,
    type: type,
    amount: amount,
    categoryId: 1,
    subcategoryId: subcategoryName == null ? null : 2,
    categoryName: categoryName,
    subcategoryName: subcategoryName,
    note: note,
    date: date,
    createdAt: date,
  );
}

Widget _wrap(Widget child, [Brightness brightness = Brightness.light]) =>
    MaterialApp(
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      darkTheme: ThemeData.dark(),
      theme: ThemeData(
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E5A44),
          brightness: brightness,
        ),
      ),
      home: Scaffold(body: child),
    );

BoxDecoration _iconTileDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const Key('transaction_tile_icon_container')),
  );
  return container.decoration as BoxDecoration;
}

Icon _iconWidget(WidgetTester tester) {
  final iconFinder = find.descendant(
    of: find.byKey(const Key('transaction_tile_icon_container')),
    matching: find.byType(Icon),
  );
  return tester.widget<Icon>(iconFinder);
}

void main() {
  testWidgets('renders the category name and note', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        TransactionTile(
          transaction: _transaction(note: 'Monthly pay'),
          onTap: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Monthly pay'), findsOneWidget);
  });

  testWidgets('prefixes income with + and formats rupiah', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TransactionTile(
          transaction: _transaction(type: 'income', amount: 100000),
          onTap: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.textContaining('+'), findsOneWidget);
    expect(find.textContaining('100.000'), findsOneWidget);
  });

  testWidgets('prefixes expense with -', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        TransactionTile(
          transaction: _transaction(type: 'expense', amount: 25000),
          onTap: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.textContaining('-'), findsOneWidget);
    expect(find.textContaining('25.000'), findsOneWidget);
  });

  testWidgets('tapping the row fires onTap', (WidgetTester tester) async {
    var tapped = false;

    await tester.pumpWidget(
      _wrap(
        TransactionTile(
          transaction: _transaction(),
          onTap: () => tapped = true,
          onDelete: () {},
        ),
      ),
    );

    await tester.tap(find.byType(TransactionTile));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('swiping the row fires onDelete', (WidgetTester tester) async {
    var deleted = false;
    var visible = true;
    late StateSetter rebuild;

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            if (!visible) return const SizedBox.shrink();
            return TransactionTile(
              transaction: _transaction(),
              onTap: () {},
              onDelete: () {
                deleted = true;
                rebuild(() => visible = false);
              },
            );
          },
        ),
      ),
    );

    await tester.drag(find.byType(Dismissible), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.byType(TransactionTile), findsNothing);
  });

  testWidgets('renders grocery tile colors in light and dark themes', (
    WidgetTester tester,
  ) async {
    final groceryTx = _transaction(
      type: 'expense',
      categoryName: 'Expense',
      subcategoryName: 'Grocery',
    );

    // Light theme grocery tokens from DESIGN.md
    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: groceryTx,
        onTap: () {},
        onDelete: () {},
      ),
      Brightness.light,
    ));

    expect(_iconTileDecoration(tester).color, const Color(0xFFE4F1E9));
    expect(_iconWidget(tester).color, const Color(0xFF0E5A44));

    // Dark theme grocery tokens from DESIGN.md
    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: groceryTx,
        onTap: () {},
        onDelete: () {},
      ),
      Brightness.dark,
    ));
    await tester.pumpAndSettle();

    expect(_iconTileDecoration(tester).color, const Color(0xFF29483B));
    expect(_iconWidget(tester).color, const Color(0xFF83DFB7));
  });

  // Food is the commonest expense in the app, and it used to be drawn in the grocery
  // green — which was the income pair, character for character. A row that spent money
  // looked like a row that earned it. The two palettes are separate now, and this is
  // the assertion that keeps them apart: it fails on the old code with #0E5A44, the
  // income icon colour, where it now expects amber.
  testWidgets('a food expense is not drawn in the income green', (
    WidgetTester tester,
  ) async {
    final foodTx = _transaction(
      type: 'expense',
      categoryName: 'Expense',
      subcategoryName: 'Food',
    );

    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: foodTx,
        onTap: () {},
        onDelete: () {},
      ),
      Brightness.light,
    ));

    expect(_iconTileDecoration(tester).color, const Color(0xFFFEF3C7));
    expect(_iconWidget(tester).color, const Color(0xFFB45309));
    expect(_iconWidget(tester).icon, Icons.restaurant);

    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: foodTx,
        onTap: () {},
        onDelete: () {},
      ),
      Brightness.dark,
    ));
    await tester.pumpAndSettle();

    expect(_iconTileDecoration(tester).color, const Color(0xFF3B2E18));
    expect(_iconWidget(tester).color, const Color(0xFFFCD34D));
  });

  testWidgets('a coffee expense shares food\'s amber, not the income green', (
    WidgetTester tester,
  ) async {
    final coffeeTx = _transaction(
      type: 'expense',
      categoryName: 'Expense',
      subcategoryName: 'Coffee Shop',
    );

    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: coffeeTx,
        onTap: () {},
        onDelete: () {},
      ),
      Brightness.light,
    ));

    expect(_iconTileDecoration(tester).color, const Color(0xFFFEF3C7));
    expect(_iconWidget(tester).color, const Color(0xFFB45309));
    expect(_iconWidget(tester).icon, Icons.local_cafe_outlined);
  });

  testWidgets('an income row keeps its own green, which food no longer borrows', (
    WidgetTester tester,
  ) async {
    final incomeTx = _transaction(type: 'income', categoryName: 'Salary');
    final foodTx = _transaction(
      type: 'expense',
      categoryName: 'Expense',
      subcategoryName: 'Food',
    );

    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: incomeTx,
        onTap: () {},
        onDelete: () {},
      ),
    ));
    final Color? incomeIcon = _iconWidget(tester).color;

    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: foodTx,
        onTap: () {},
        onDelete: () {},
      ),
    ));

    expect(_iconWidget(tester).color, isNot(incomeIcon),
        reason: 'the glyph alone is not enough to tell a spend from a payment');
  });

  testWidgets('renders entertainment tile colors in light and dark themes', (
    WidgetTester tester,
  ) async {
    final entertainmentTx = _transaction(
      type: 'expense',
      categoryName: 'Entertainment',
    );

    // Light theme entertainment tokens from DESIGN.md
    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: entertainmentTx,
        onTap: () {},
        onDelete: () {},
      ),
      Brightness.light,
    ));

    expect(_iconTileDecoration(tester).color, const Color(0xFFEEF0F5));
    expect(_iconWidget(tester).color, const Color(0xFF4338CA));

    // Dark theme entertainment tokens from DESIGN.md
    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: entertainmentTx,
        onTap: () {},
        onDelete: () {},
      ),
      Brightness.dark,
    ));
    await tester.pumpAndSettle();

    expect(_iconTileDecoration(tester).color, const Color(0xFF353E4C));
    expect(_iconWidget(tester).color, const Color(0xFFC7D2FE));
  });

  testWidgets('renders income tile colors in light and dark themes', (
    WidgetTester tester,
  ) async {
    final incomeTx = _transaction(
      type: 'income',
      categoryName: 'Salary',
    );

    // Light theme income tokens from DESIGN.md
    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: incomeTx,
        onTap: () {},
        onDelete: () {},
      ),
      Brightness.light,
    ));

    expect(_iconTileDecoration(tester).color, const Color(0xFFD1FAE5));
    expect(_iconWidget(tester).color, const Color(0xFF0E5A44));

    // Dark theme income tokens from DESIGN.md
    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: incomeTx,
        onTap: () {},
        onDelete: () {},
      ),
      Brightness.dark,
    ));
    await tester.pumpAndSettle();

    expect(_iconTileDecoration(tester).color, const Color(0xFF24473B));
    expect(_iconWidget(tester).color, const Color(0xFF83DFB7));
  });

  testWidgets('provides accessible semantic labels on icons', (
    WidgetTester tester,
  ) async {
    final groceryTx = _transaction(
      type: 'expense',
      categoryName: 'Grocery',
    );

    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: groceryTx,
        onTap: () {},
        onDelete: () {},
      ),
    ));

    // Accessible category icon
    final icon = _iconWidget(tester);
    expect(icon.semanticLabel, 'Grocery');
    expect(icon.icon, Icons.shopping_cart_outlined);

    // The dismissal background is mounted only while swiping.
    await tester.drag(find.byType(Dismissible), const Offset(-40, 0));
    await tester.pump();
    final deleteIconFinder = find.byWidgetPredicate(
      (Widget w) =>
          w is Icon &&
          w.icon == Icons.delete_outline &&
          w.semanticLabel == 'Delete transaction',
    );
    expect(deleteIconFinder, findsOneWidget);
  });

  testWidgets('applies dark theme surface, border, and amount text contrast', (
    WidgetTester tester,
  ) async {
    final expenseTx = _transaction(
      type: 'expense',
      amount: 45000,
      categoryName: 'Other Needs',
    );

    await tester.pumpWidget(_wrap(
      TransactionTile(
        transaction: expenseTx,
        onTap: () {},
        onDelete: () {},
      ),
      Brightness.dark,
    ));

    // Outer card container
    final inkWellFinder = find.byType(InkWell);
    final cardContainer = tester.widget<Container>(
      find.descendant(of: inkWellFinder, matching: find.byType(Container)).first,
    );
    final cardDecoration = cardContainer.decoration as BoxDecoration;
    final cardBorder = cardDecoration.border as Border;

    expect(cardDecoration.color, const Color(0xFF1B2924)); // dark-surface
    expect(cardBorder.top.color, const Color(0xFF31443A)); // dark-border

    // Expense amount color in dark theme (dark-error WCAG compliant)
    final amountText = tester.widget<Text>(find.textContaining('45.000'));
    expect(amountText.style?.color, const Color(0xFFFF8A8A));
  });
}

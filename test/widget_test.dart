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

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

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
}

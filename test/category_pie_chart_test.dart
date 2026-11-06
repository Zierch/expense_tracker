import 'package:expense_tracker/presentation/widgets/category_pie_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('donut legend shows category percentages', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CategoryPieChart(
      data: const {'Food': 75, 'Fuel': 25},
      colorFor: (_) => Colors.green,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('75.0%'), findsOneWidget);
    expect(find.text('25.0%'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
  });
}

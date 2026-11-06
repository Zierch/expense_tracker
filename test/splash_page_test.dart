import 'package:expense_tracker/presentation/pages/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('splash displays the brand and tagline', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashPage()));
    expect(find.text('ExpenseTracker'), findsOneWidget);
    expect(find.text('Track smarter, spend better.'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}

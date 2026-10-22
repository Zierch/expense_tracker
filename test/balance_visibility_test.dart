// The dashboard shows the month's balance until the eye on the card is tapped,
// and remembers that for the next launch.
//
// The figure is pinned here instead of read from a database: what these tests
// are about is the eye and what it does to the card, not the summary query —
// that query is pinned in `home_dashboard_test.dart`.

import 'package:expense_tracker/domain/entities/summary_result.dart';
import 'package:expense_tracker/presentation/providers/balance_visibility_provider.dart';
import 'package:expense_tracker/presentation/providers/theme_provider.dart';
import 'package:expense_tracker/presentation/widgets/summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A month whose three figures are easy to tell apart on the card.
SummaryResult _summary() => SummaryResult(
      totalIncome: 5000000,
      totalExpense: 500000,
      balance: 4500000,
      expenseByCategory: const <String, double>{},
      incomeByCategory: const <String, double>{},
    );

/// Every piece of text the card is currently showing.
String _cardText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text text) => text.data ?? '')
    .join(' | ');

/// What the card renders for [amount].
String _rupiah(double amount) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(amount);

/// The card on its own, over [prefs] as the store behind the eye.
Future<void> _pumpCard(WidgetTester tester, SharedPreferences prefs) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: Scaffold(
        body: SummaryCard(summaryAsync: AsyncValue.data(_summary())),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// A container over [prefs]: reading one is what a launch does.
ProviderContainer _launch(SharedPreferences prefs) => ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  test('an untouched install has the balance on screen', () {
    expect(_launch(prefs).read(balanceVisibleProvider), isTrue,
        reason: 'the eye is an option, not a new default: someone who never '
            'taps it sees the card exactly as it was before');
  });

  test('the choice outlives the container that made it', () async {
    _launch(prefs).read(balanceVisibleProvider.notifier).toggle();
    // The write is fire-and-forget (the visible change must not wait on a disk),
    // so the store is given its turn before the next launch reads it.
    await pumpEventQueue();

    expect(_launch(prefs).read(balanceVisibleProvider), isFalse,
        reason: 'hiding the balance for one session and then opening the app to '
            'it shown again would be worse than having no toggle');
  });

  testWidgets('the eye takes the figure off the card and puts it back',
      (WidgetTester tester) async {
    await _pumpCard(tester, prefs);

    expect(_cardText(tester), contains(_rupiah(4500000)),
        reason: 'the tap below is about hiding a figure that is actually there');
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(_cardText(tester), isNot(contains(_rupiah(4500000))),
        reason: 'the reason the toggle exists: the month\'s balance is no '
            'longer readable over a shoulder');
    expect(_cardText(tester), contains('Rp ••••••'),
        reason: 'and the row says so rather than showing an empty gap');
    expect(_cardText(tester), contains(_rupiah(500000)),
        reason: 'income and expense are the entries the user made, not the '
            'figure being hidden, so they stay');
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget,
        reason: 'the way back has to be the control the user just used');

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();

    expect(_cardText(tester), contains(_rupiah(4500000)));
  });

  testWidgets('a launch that starts hidden shows no figure, not even briefly',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'balanceVisible': false});
    prefs = await SharedPreferences.getInstance();

    await _pumpCard(tester, prefs);

    expect(_cardText(tester), isNot(contains(_rupiah(4500000))),
        reason: 'the choice is read while the card is built, so the first frame '
            'is already the hidden one');
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });
}
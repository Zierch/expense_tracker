// The dashboard's month picker: it names the month on the screen, offers
// months only, and refuses the ones outside its bounds.
//
// The bounds are passed in explicitly here rather than read from the clock, so
// what "the newest month there can be data for" means does not change with the
// day the suite runs — the dashboard's own call passes `DateTime.now()`, and
// that call is the only clock-dependent part.

import 'package:expense_tracker/presentation/widgets/month_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dashboard's month, held the way the dashboard holds it, so the label
/// follows a choice.
class _Dashboard extends StatefulWidget {
  const _Dashboard({required this.initial});

  final DateTime initial;

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  late DateTime _month = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MonthSelector(
        month: _month,
        onChanged: (DateTime month) => setState(() => _month = month),
      ),
    );
  }
}

Future<void> _pumpDashboard(WidgetTester tester, DateTime month) async {
  await tester.pumpWidget(MaterialApp(home: _Dashboard(initial: month)));
}

/// A page whose one button opens [showMonthPicker] over fixed bounds, so the
/// assertions below do not depend on when the suite runs.
Future<void> _pumpPicker(
  WidgetTester tester, {
  required DateTime selected,
  required DateTime firstMonth,
  required DateTime lastMonth,
  required ValueChanged<DateTime?> onResult,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async => onResult(await showMonthPicker(
            context,
            selected: selected,
            firstMonth: firstMonth,
            lastMonth: lastMonth,
          )),
          child: const Text('open'),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Whether the month button labelled [label] can be tapped.
bool _monthOffered(WidgetTester tester, String label) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, label)).onPressed !=
    null;

/// Whether the year arrow [icon] can be tapped.
bool _yearSteppable(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon)).onPressed !=
    null;

void main() {
  testWidgets('the dashboard names the month it is showing', (tester) async {
    await _pumpDashboard(tester, DateTime(2026, 3, 15));

    expect(find.text('March 2026'), findsOneWidget,
        reason: 'the app bar icon this replaced changed the screen without '
            'saying what it changed it to');
  });

  testWidgets('tapping the name opens a picker of months', (tester) async {
    await _pumpDashboard(tester, DateTime(2026, 3, 15));

    await tester.tap(find.text('March 2026'));
    await tester.pumpAndSettle();

    expect(find.text('Select month'), findsOneWidget);
    expect(find.text('Jan'), findsOneWidget,
        reason: 'the months are laid out together, which is the whole point: '
            'the date picker asked for a day first');
  });

  testWidgets('a chosen month comes back as its first day', (tester) async {
    DateTime? result;

    await _pumpPicker(
      tester,
      selected: DateTime(2026, 3, 15),
      firstMonth: DateTime(2020),
      lastMonth: DateTime(2026, 10, 22),
      onResult: (DateTime? picked) => result = picked,
    );

    await tester.tap(find.widgetWithText(TextButton, 'May'));
    await tester.pumpAndSettle();

    expect(result, DateTime(2026, 5, 1),
        reason: 'a month anchor, not the day of the month that happened to be '
            'selected before: the dashboard reads year and month only');
  });

  testWidgets('months outside the bounds are shown but not offered',
      (tester) async {
    await _pumpPicker(
      tester,
      selected: DateTime(2026, 3),
      firstMonth: DateTime(2020, 6),
      lastMonth: DateTime(2026, 10, 22),
      onResult: (_) {},
    );

    expect(find.text('Jan'), findsOneWidget,
        reason: 'a month that cannot be picked is visible rather than missing');
    expect(_monthOffered(tester, 'Jun'), isTrue,
        reason: 'the bound is the month itself, not the year it sits in');
    expect(_monthOffered(tester, 'May'), isFalse);
    expect(_monthOffered(tester, 'Oct'), isTrue,
        reason: "today's month is the newest there is data for");
    expect(_monthOffered(tester, 'Nov'), isFalse,
        reason: 'a month with no data yet must not be selectable');
    expect(_monthOffered(tester, 'Dec'), isFalse);
  });

  testWidgets('the year arrows stop at both bounds', (tester) async {
    await _pumpPicker(
      tester,
      selected: DateTime(2020, 7),
      firstMonth: DateTime(2020, 6),
      lastMonth: DateTime(2026, 10, 22),
      onResult: (_) {},
    );

    expect(find.text('2020'), findsOneWidget);
    expect(_yearSteppable(tester, Icons.chevron_left), isFalse,
        reason: 'no year before the earliest one the app can show');

    for (int year = 2021; year <= 2026; year++) {
      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
      await tester.pumpAndSettle();
    }

    expect(find.text('2026'), findsOneWidget);
    expect(_yearSteppable(tester, Icons.chevron_right), isFalse,
        reason: 'and no year after the one today falls in');
    expect(_monthOffered(tester, 'Oct'), isTrue);
    expect(_monthOffered(tester, 'Nov'), isFalse,
        reason: 'the bound is a month, so it still bites inside the last year');
  });

  testWidgets('dismissing the picker is not a choice', (tester) async {
    DateTime? result = DateTime(2000);
    bool answered = false;

    await _pumpPicker(
      tester,
      selected: DateTime(2026, 3),
      firstMonth: DateTime(2020),
      lastMonth: DateTime(2026, 10, 22),
      onResult: (DateTime? picked) {
        answered = true;
        result = picked;
      },
    );

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(answered, isTrue);
    expect(result, isNull,
        reason: 'dismissing must leave the month on screen as it was');
  });
}
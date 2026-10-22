// The dashboard's month, named on the screen and changed from there.
//
// The dashboard filters by one month and nothing finer: `MonthRange` reduces it
// to (year, month) and no consumer ever reads the day. The platform
// `showDatePicker` is a *date* picker, so it asked for a day whose value went
// nowhere, from an app-bar icon that changed the screen without saying which
// month was now on it. This replaces that pair for the dashboard: the month is
// named above the card, and the picker only offers months.
//
// The statistics page keeps its own month and its own date picker. The two
// screens are opened one at a time and are not meant to move together, so a
// shared selection would make opening one silently change the other.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// How far back the picker offers months, matching the bound the date picker
/// this replaced used.
final DateTime _firstMonth = DateTime(2020);

/// The dashboard's month as a label that opens [showMonthPicker].
class MonthSelector extends StatelessWidget {
  final DateTime month;

  /// Called with the chosen month, always midnight on its first day.
  final ValueChanged<DateTime> onChanged;

  const MonthSelector({super.key, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final DateTime? picked = await showMonthPicker(
              context,
              selected: month,
              firstMonth: _firstMonth,
              // Today's month is the newest one there can be data for; the day is
              // not part of the bound.
              lastMonth: DateTime.now(),
            );
            if (picked != null) onChanged(picked);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  DateFormat('MMMM yyyy').format(month),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for one month, between [firstMonth] and [lastMonth] inclusive.
///
/// Resolves to midnight on the first day of the chosen month — a month anchor,
/// not a date — or to `null` when dismissed. The year is the only step: the
/// months of one year are laid out together, and the ones outside the bounds are
/// shown but not selectable, so a month that cannot be picked is visible rather
/// than mysteriously absent.
Future<DateTime?> showMonthPicker(
  BuildContext context, {
  required DateTime selected,
  required DateTime firstMonth,
  required DateTime lastMonth,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (BuildContext context) => _MonthPickerDialog(
      selected: selected,
      firstMonth: firstMonth,
      lastMonth: lastMonth,
    ),
  );
}

class _MonthPickerDialog extends StatefulWidget {
  final DateTime selected;
  final DateTime firstMonth;
  final DateTime lastMonth;

  const _MonthPickerDialog({
    required this.selected,
    required this.firstMonth,
    required this.lastMonth,
  });

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  /// Short month names, from the formatter rather than a list in here, so a
  /// locale that names them differently is followed rather than overridden.
  static final List<String> _names = <String>[
    for (int month = 1; month <= 12; month++)
      DateFormat.MMM().format(DateTime(2000, month)),
  ];

  late int _year = widget.selected.year;

  /// The first day of [month] in the year on screen.
  DateTime _anchor(int month) => DateTime(_year, month);

  /// Whether [month] of the year on screen falls inside the bounds.
  bool _isOffered(int month) {
    final DateTime anchor = _anchor(month);
    return !anchor.isBefore(DateTime(widget.firstMonth.year, widget.firstMonth.month)) &&
        !anchor.isAfter(DateTime(widget.lastMonth.year, widget.lastMonth.month));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Select month'),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  onPressed: _year > widget.firstMonth.year
                      ? () => setState(() => _year--)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous year',
                ),
                // Fixed width so the arrows do not move as the year changes digit
                // count, or as the buttons enable and disable at the bounds.
                SizedBox(
                  width: 72,
                  child: Text(
                    '$_year',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: _year < widget.lastMonth.year
                      ? () => setState(() => _year++)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next year',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: <Widget>[
                for (int month = 1; month <= 12; month++) _monthButton(month),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _monthButton(int month) {
    final bool offered = _isOffered(month);
    final bool isSelected = offered &&
        _year == widget.selected.year &&
        month == widget.selected.month;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return TextButton(
      // The chosen month is one tap: no confirmation step to forget, and no day
      // to pick on the way.
      onPressed: offered ? () => Navigator.of(context).pop(_anchor(month)) : null,
      style: TextButton.styleFrom(
        minimumSize: const Size(84, 40),
        backgroundColor: isSelected ? scheme.primaryContainer : null,
        foregroundColor: isSelected ? scheme.onPrimaryContainer : null,
      ),
      child: Text(_names[month - 1]),
    );
  }
}
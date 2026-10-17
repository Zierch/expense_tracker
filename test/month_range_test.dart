// Month membership, pinned at the boundaries.
//
// The home page used to filter a month by hand with
// `isAfter(startOfMonth - 1 day) && isBefore(endOfMonth + 1 day)`. Midnight of the
// previous month's last day is *after* that lower bound, and the upper bound landed a
// day past month end, so the list showed two whole days that the SQL total directly
// above it counted neither of. The rows on screen did not add up to the total on
// screen. The same range was written out three times and only that one copy was
// wrong, which is why the definition now lives in `MonthRange` and why these tests
// exist: to hold both bounds to what they mean, and to stop the range being written
// out per page again.

import 'dart:io';

import 'package:expense_tracker/domain/entities/month_range.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sources that must agree about what a month contains, and the tokens proving each
/// asks `MonthRange` instead of working the bounds out itself.
///
/// The home page lists a month, the statistics page buckets one, and the export
/// writes one to Drive. All three read the same totals, so all three have to draw the
/// month boundaries in the same place. These are existence checks on the call sites,
/// not proof that nothing else in the file compares dates.
const Map<String, List<String>> _monthConsumers = <String, List<String>>{
  'lib/presentation/pages/home_page.dart': <String>[
    'MonthRange.of(',
    'range.contains(',
  ],
  'lib/presentation/pages/statistics_page.dart': <String>[
    'MonthRange.of(',
    'contains(',
  ],
  'lib/domain/usecases/export_month_usecase.dart': <String>[
    'MonthRange.of(',
    'range.start',
    'range.end',
  ],
};

/// Shapes that mean "a month boundary was worked out here".
///
/// The first four are the old home-page filter; the last is the old statistics-page
/// bound (`DateTime(y, m + 1, 0, 23, 59, 59)`), correct but another hand-written copy.
/// A *renamed* re-derivation — `where((t) => t.date.month == m)`, say — still slips
/// through: catching that needs a behavioural test over the widget tree, not a text
/// scan. What this catches is the return of a shape that was here before, in any file
/// rather than in a list of three.
const List<String> _handWrittenBoundShapes = <String>[
  'startOfMonth',
  'endOfMonth',
  '.add(const Duration(days: 1))',
  '.subtract(const Duration(days: 1))',
  ', 0, 23, 59',
];

/// The one file allowed to work out a month end.
///
/// `DateTime(year, month + 1, 0)` is the idiomatic Dart way to write "the last day of
/// the month", and it is what the statistics page used to do. It is sanctioned inside
/// `MonthRange` because that is where month arithmetic is supposed to live; anywhere
/// else it is one more hand-written boundary, free to disagree with the others.
const String _monthArithmeticHome = 'lib/domain/entities/month_range.dart';

/// Mid-October, chosen so the month has a neighbour day on each side.
final MonthRange _october = MonthRange.of(DateTime(2026, 10, 15));

/// [source] with its whole-line `//` comments dropped.
///
/// These guards are about code, not prose. A comment recording what the range used to
/// look like is the opposite of a regression, and must not trip a guard that exists to
/// catch the shape coming back as code.
///
/// The name is deliberately not `_codeLines`: `release_config_test.dart` has a
/// `_codeLines` that also drops block comments, and two different classifiers behind
/// one name is how a maintainer comes to trust the weaker one. The narrower contract
/// here leaves one false positive open — a block or trailing comment naming a
/// forbidden shape would fail the guard — and every such comment in this project is a
/// whole-line `//`, so the scan stays honest about its shape instead of half-parsing
/// strings for `//`.
String _withoutLineComments(String source) => source
    .split('\n')
    .where((String line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// Every Dart source under `lib/`, as (path, comment-stripped source) pairs.
///
/// Read off the disk rather than from a hand-kept list, so a new page that works out
/// its own month bounds lands inside the scan instead of outside it. Paths are
/// normalised to `/` because this runs on Windows during `flutter test`.
List<MapEntry<String, String>> _libSources() {
  final List<MapEntry<String, String>> sources = <MapEntry<String, String>>[];
  for (final FileSystemEntity entity
      in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Generated sources are skipped: `.g.dart` from drift, `.freezed.dart` from
    // freezed. They are machine output from the schema and the entities, both of
    // which the scan does cover, so nothing a human wrote is hidden by this; and a
    // token that appeared only after a `build_runner` run would surface as a mystery
    // failure in generated code.
    if (entity.path.endsWith('.g.dart') ||
        entity.path.endsWith('.freezed.dart')) {
      continue;
    }
    sources.add(MapEntry<String, String>(
      entity.path.replaceAll('\\', '/'),
      _withoutLineComments(entity.readAsStringSync()),
    ));
  }
  return sources;
}

void main() {
  group('the bounds of a month', () {
    test('start is midnight on the 1st and before end', () {
      expect(_october.start, DateTime(2026, 10, 1));
      expect(_october.start.day, 1);
      expect(_october.start.hour, 0);
      expect(_october.start.minute, 0);
      expect(_october.start.second, 0);
      expect(_october.start.isBefore(_october.end), isTrue);
    });

    test('includes the very first instant of the month', () {
      expect(_october.contains(DateTime(2026, 10, 1)), isTrue);
    });

    test('includes the 1st carrying a time of day', () {
      // Rows written before the add page normalised its date really do carry a
      // time, so the lower bound has to be inclusive rather than "after midnight".
      expect(_october.contains(DateTime(2026, 10, 1, 0, 0, 0, 1)), isTrue);
      expect(_october.contains(DateTime(2026, 10, 1, 9, 15, 30)), isTrue);
    });

    test('includes the last day at its last second', () {
      expect(_october.contains(DateTime(2026, 10, 31, 23, 59, 59)), isTrue);
    });

    test('includes the last day in its final microsecond', () {
      expect(
        _october.contains(DateTime(2026, 10, 31, 23, 59, 59, 999, 999)),
        isTrue,
      );
    });

    test('includes the last day entered at midday', () {
      expect(_october.contains(DateTime(2026, 10, 31, 14, 30)), isTrue);
    });

    test('includes a mid-month instant whatever time it carries', () {
      expect(_october.contains(DateTime(2026, 10, 15, 12, 34, 56)), isTrue);
      expect(_october.contains(DateTime(2026, 10, 15)), isTrue);
    });
  });

  group('the days the hand-written range used to leak', () {
    test('excludes the previous month\'s last day at its last second', () {
      final DateTime at = DateTime(2026, 9, 30, 23, 59, 59);

      // The shape of the bound this replaced. It is reproduced here so the test
      // fails loudly if someone reintroduces it, and so the bug it caused is
      // documented rather than just asserted away.
      final DateTime oldLowerBound =
          DateTime(2026, 10, 1).subtract(const Duration(days: 1));
      expect(at.isAfter(oldLowerBound), isTrue,
          reason: 'the old lower bound really did let this day through');

      expect(_october.contains(at), isFalse);
    });

    test('excludes every hour of the previous month\'s last day', () {
      final DateTime oldLowerBound =
          DateTime(2026, 10, 1).subtract(const Duration(days: 1));

      for (int hour = 0; hour < 24; hour++) {
        final DateTime at = DateTime(2026, 9, 30, hour, 30);
        expect(at.isAfter(oldLowerBound), isTrue,
            reason: 'the old bound let ${hour}h through, which was the bug');
        expect(_october.contains(at), isFalse);
      }
    });

    test('excludes the next month\'s first day at midnight', () {
      final DateTime at = DateTime(2026, 11, 1);

      final DateTime oldUpperBound =
          DateTime(2026, 10, 31, 23, 59, 59).add(const Duration(days: 1));
      expect(at.isBefore(oldUpperBound), isTrue,
          reason: 'the old upper bound really did let this day through');

      expect(_october.contains(at), isFalse);
    });

    test('excludes every hour of the next month\'s first day', () {
      final DateTime oldUpperBound =
          DateTime(2026, 10, 31, 23, 59, 59).add(const Duration(days: 1));

      for (int hour = 0; hour < 24; hour++) {
        final DateTime at = DateTime(2026, 11, 1, hour, 30);
        expect(at.isBefore(oldUpperBound), isTrue,
            reason: 'the old bound let ${hour}h through, which was the bug');
        expect(_october.contains(at), isFalse);
      }
    });

    test('excludes the neighbours of the neighbouring months too', () {
      expect(_october.contains(DateTime(2026, 9, 29, 23, 59, 59)), isFalse);
      expect(_october.contains(DateTime(2026, 11, 2)), isFalse);
    });
  });

  group('the bound the database compares against', () {
    test('neither truncates the final second nor spills into the next month', () {
      expect(_october.end.isAfter(DateTime(2026, 10, 31, 23, 59, 59)), isTrue,
          reason: 'a row in the last second of the month must not be dropped');
      expect(_october.end.isBefore(DateTime(2026, 11, 1)), isTrue,
          reason: 'the bound must not reach into the next month');
    });

    test('is the exact value handed to the database', () {
      // What drift *does* with this value is not observable from here, and an earlier
      // version of this test pretended otherwise: it truncated the bound itself with
      // `~/ 1000` and asserted the result, which holds for any instant in the final
      // second no matter how the package converts. The conversion is pinned
      // end-to-end in `month_range_sql_test.dart` instead, where a row is written,
      // read back, and selected through a real `isBetween`.
      expect(_october.end, DateTime(2026, 10, 31, 23, 59, 59, 999, 999));
      expect(_october.contains(DateTime(2026, 11, 1)), isFalse);
    });
  });

  group('how long a month is', () {
    test('February 2026 is 28 days', () {
      expect(MonthRange.of(DateTime(2026, 2, 15)).dayCount, 28);
    });

    test('February 2024 is 29 days', () {
      expect(MonthRange.of(DateTime(2024, 2, 15)).dayCount, 29);
    });

    test('February 2000 is 29 days and February 1900 is 28', () {
      // The century rule, so a hand-rolled leap-year check cannot creep in and get
      // the divisible-by-100 case wrong.
      expect(MonthRange.of(DateTime(2000, 2, 15)).dayCount, 29);
      expect(MonthRange.of(DateTime(1900, 2, 15)).dayCount, 28);
    });

    test('30- and 31-day months', () {
      expect(MonthRange.of(DateTime(2026, 4, 10)).dayCount, 30);
      expect(MonthRange.of(DateTime(2026, 11, 10)).dayCount, 30);
      expect(MonthRange.of(DateTime(2026, 7, 10)).dayCount, 31);
      expect(MonthRange.of(DateTime(2026, 1, 10)).dayCount, 31);
    });

    test('end lands on the day dayCount names, for every length', () {
      for (final DateTime anchor in <DateTime>[
        DateTime(2026, 1, 15),
        DateTime(2026, 2, 15),
        DateTime(2024, 2, 15),
        DateTime(2026, 4, 15),
        DateTime(2026, 10, 15),
        DateTime(2026, 12, 15),
      ]) {
        final MonthRange range = MonthRange.of(anchor);
        expect(range.end.day, range.dayCount,
            reason: '${range.year}-${range.month} must end on its own last day');
      }
    });

    test('every day of a leap February is inside it, and March 1st is not', () {
      final MonthRange february = MonthRange.of(DateTime(2024, 2, 9, 8, 15));

      for (int dayOfMonth = 1; dayOfMonth <= february.dayCount; dayOfMonth++) {
        final DateTime at = february.day(dayOfMonth);
        expect(at.day, dayOfMonth);
        expect(february.contains(at), isTrue,
            reason: 'February 2024 day $dayOfMonth must be inside the month');
        expect(february.contains(DateTime(2024, 2, dayOfMonth, 23, 59, 59)),
            isTrue);
      }

      expect(february.contains(DateTime(2024, 3, 1)), isFalse);
      expect(february.contains(DateTime(2024, 2, 29, 23, 59, 59)), isTrue);
      expect(february.contains(DateTime(2024, 2, 30)), isFalse);
    });
  });

  group('year boundaries', () {
    test('December ends in December and next January is outside', () {
      final MonthRange december = MonthRange.of(DateTime(2026, 12, 15, 23, 59));

      expect(december.year, 2026);
      expect(december.month, 12);
      expect(december.end.year, 2026);
      expect(december.end.month, 12);
      expect(december.dayCount, 31);
      expect(december.contains(DateTime(2026, 12, 31, 23, 59, 59)), isTrue);
      expect(december.contains(DateTime(2027, 1, 1)), isFalse);
    });

    test('January does not reach back into the previous December', () {
      final MonthRange january = MonthRange.of(DateTime(2026, 1, 1));

      expect(january.start, DateTime(2026, 1, 1));
      expect(january.end.year, 2026);
      expect(january.end.month, 1);
      expect(january.dayCount, 31);
      expect(january.contains(DateTime(2025, 12, 31, 23, 59, 59)), isFalse);
      expect(january.contains(DateTime(2026, 1, 1)), isTrue);
    });
  });

  group('the anchor', () {
    test('its time of day and day of month are ignored', () {
      // The home page holds `DateTime.now()` and swaps in whatever the month picker
      // returns, so both a fresh page and a picked month have to describe the same
      // range as the 1st at midnight would.
      final MonthRange withTime =
          MonthRange.of(DateTime(2026, 3, 17, 14, 30, 45, 123, 456));
      final MonthRange fromTheFirst = MonthRange.of(DateTime(2026, 3, 1));

      expect(withTime.year, fromTheFirst.year);
      expect(withTime.month, fromTheFirst.month);
      expect(withTime.start, fromTheFirst.start);
      expect(withTime.end, fromTheFirst.end);
      expect(withTime.dayCount, fromTheFirst.dayCount);
    });
  });

  group('day()', () {
    test('day 1 is start and every other day is midnight on that date', () {
      expect(_october.day(1), _october.start);

      for (int dayOfMonth = 1; dayOfMonth <= _october.dayCount; dayOfMonth++) {
        final DateTime at = _october.day(dayOfMonth);
        expect(at.year, 2026);
        expect(at.month, 10);
        expect(at.day, dayOfMonth);
        expect(at.hour, 0);
        expect(at.minute, 0);
        expect(at.second, 0);
      }
    });

    test('refuses a day outside the month instead of folding it in', () {
      // `DateTime` quietly turns day 0 and day 32 into the neighbouring months, so a
      // future caller would put a wrong date on a summary label without failing. The
      // assert runs where tests run; it is deliberately not a thrown error, so a
      // release build cannot crash on a label.
      expect(() => _october.day(0), throwsA(isA<AssertionError>()));
      expect(() => _october.day(32), throwsA(isA<AssertionError>()));
      expect(() => _october.day(1), returnsNormally);
      expect(() => _october.day(_october.dayCount), returnsNormally);
    });

    test('the last day is the one statistics labels a week with', () {
      // `_weeklyBuckets` builds its "Week n · 29 Oct – 31 Oct" label from these two,
      // so off-by-one here would mislabel a summary rather than throw.
      expect(_october.day(_october.dayCount), DateTime(2026, 10, 31));
      expect(_october.contains(_october.day(_october.dayCount)), isTrue);
    });
  });

  group('no screen re-derives a month range by hand', () {
    // The range this replaced was written out three times, and the copy on the home
    // page was the one that drifted. A guard on the shape of the old code is cheap;
    // noticing that a list no longer agrees with the total above it is not.
    test('every month consumer takes its bounds from MonthRange', () {
      for (final MapEntry<String, List<String>> consumer
          in _monthConsumers.entries) {
        final String source =
            _withoutLineComments(File(consumer.key).readAsStringSync());

        for (final String required in consumer.value) {
          expect(source, contains(required),
              reason: '${consumer.key} must use MonthRange ($required)');
        }
      }
    });

    test('the scan reads the app rather than walking an empty tree', () {
      // Without this, a moved directory would make the scan below pass by finding
      // nothing to scan at all.
      final List<MapEntry<String, String>> sources = _libSources();

      // A floor rather than a count: the point is to catch a path that silently
      // matches nothing, not to pin how many files the app has.
      expect(sources.length, greaterThan(15));
      expect(
        sources.map((MapEntry<String, String> entry) => entry.key),
        containsAll(<String>[
          'lib/presentation/pages/home_page.dart',
          'lib/domain/entities/month_range.dart',
        ]),
      );
    });

    test('no file in lib/ reintroduces a hand-written month bound', () {
      for (final MapEntry<String, String> source in _libSources()) {
        for (final String shape in _handWrittenBoundShapes) {
          expect(source.value, isNot(contains(shape)),
              reason: '${source.key} must not work out month bounds by hand '
                  '($shape)');
        }
      }
    });

    test('no file outside MonthRange builds a day-zero month end', () {
      // The token list above catches the old statistics bound because it carried a
      // time; this catches the same idea without one. Without the single exemption
      // this scan is impossible to satisfy, because `dayCount` is written exactly
      // that way — and that is the point: month arithmetic has one home.
      for (final MapEntry<String, String> source in _libSources()) {
        if (source.key == _monthArithmeticHome) continue;

        expect(source.value, isNot(contains(', 0)')),
            reason: '${source.key} must not build a month end by hand; '
                'MonthRange owns month arithmetic');
      }
    });
  });
}

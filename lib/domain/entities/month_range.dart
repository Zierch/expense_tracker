/// The span of one calendar month, as every month filter in the app means it.
///
/// A transaction belongs to a month when its *day* falls inside it, whatever time
/// of day it was entered at. That distinction matters here: a fresh add page used
/// to seed its date with `DateTime.now()`, while the date picker returns midnight,
/// so rows carrying a time-of-day and rows without one both exist in the database.
/// A comparison written out per page got this wrong in one place and right in
/// another, so the definition lives in a single object now.
///
/// [end] is the last instant of the month. Drift stores `dateTime()` as Unix seconds,
/// and `isBetween` is inclusive at both ends, so this bound must not spill into the
/// next month and must not truncate the final day either. One microsecond past the
/// last second satisfies both: the database floors the value back to 23:59:59 as it
/// converts it (drift's own conversion, pinned end-to-end by
/// `test/month_range_sql_test.dart`), while [contains] stays correct for any
/// `DateTime` it is handed — including the sub-second fixtures a test repository can
/// produce, which rows read back from the database never are.
///
/// The bounds are local time and assume midnight exists. That holds for every zone
/// this app runs in (`id_ID` has no DST), but a zone that skipped a month's first
/// midnight would resolve [start] onto a non-existent wall time, so this is the app's
/// month filter rather than a general-purpose date library.
class MonthRange {
  MonthRange.of(DateTime anchor)
      : year = anchor.year,
        month = anchor.month,
        start = DateTime(anchor.year, anchor.month, 1),
        end = DateTime(anchor.year, anchor.month + 1, 1)
            .subtract(const Duration(microseconds: 1));

  final int year;
  final int month;

  /// First instant of the month. Inclusive.
  final DateTime start;

  /// Last representable instant of the month. Inclusive.
  final DateTime end;

  /// Whether [date] belongs to this month.
  ///
  /// The same predicate as handing [start] and [end] to the repository, so a list
  /// filtered in memory cannot disagree with a total computed in SQL. Both
  /// boundaries belong to this month and neither neighbour does.
  bool contains(DateTime date) => !date.isBefore(start) && !date.isAfter(end);

  /// Number of days in the month, which is 28, 29, 30 or 31.
  int get dayCount => DateTime(year, month + 1, 0).day;

  /// Midnight on [dayOfMonth] of this month, for labels and date arithmetic.
  ///
  /// Asserts the day is inside the month: `DateTime` would otherwise fold `0` and
  /// `32` into the neighbouring months and put a wrong date on a summary label
  /// without failing.
  DateTime day(int dayOfMonth) {
    assert(
      dayOfMonth >= 1 && dayOfMonth <= dayCount,
      'day $dayOfMonth is outside $year-$month, which has $dayCount days',
    );
    return DateTime(year, month, dayOfMonth);
  }

  /// The whole Monday–Sunday weeks this month touches, first to last.
  ///
  /// The weekly section of the statistics page groups by week, and a week is a week:
  /// the one that holds the 1st starts on the Monday before it, even when that Monday
  /// is in the previous month, and the one that holds the last day runs to its Sunday
  /// even when that Sunday is in the next. Clipping at the month edge is what made a
  /// spend on the 30th of September belong to no week of October at all.
  ///
  /// There are four, five or six of them; [contains] still describes the month alone,
  /// so a caller has to decide which of the two spans it means.
  List<WeekSpan> get weeks {
    final DateTime firstMonday = _mondayOf(start);
    final DateTime lastMonday = _mondayOf(day(dayCount));

    final List<WeekSpan> spans = <WeekSpan>[];
    for (DateTime monday = firstMonday;
        !monday.isAfter(lastMonday);
        monday = DateTime(monday.year, monday.month, monday.day + 7)) {
      spans.add(WeekSpan._(monday));
    }
    return spans;
  }

  /// Midnight on the Monday of [day]'s week.
  ///
  /// `weekday` is 1 for Monday, and the `DateTime` constructor folds a non-positive
  /// day into the previous month, so this needs no hand-written month stepping.
  static DateTime _mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - 1));

  @override
  String toString() => 'MonthRange($year-${month.toString().padLeft(2, '0')})';
}

/// One Monday-to-Sunday week, as [MonthRange.weeks] hands them out.
///
/// The week is whole rather than clipped to the month that asked for it, which is why
/// the weeks of a month can add up to more than the month's own total: the days either
/// side belong to the week they were spent in. A spend entered on Saturday the 1st is
/// part of the week it happened in, not of a seven-day span invented at the boundary.
class WeekSpan {
  WeekSpan._(DateTime monday)
      : start = DateTime(monday.year, monday.month, monday.day),
        lastDay = DateTime(monday.year, monday.month, monday.day + 6);

  /// Monday, midnight. Inclusive.
  final DateTime start;

  /// Sunday, midnight — the day the label names.
  final DateTime lastDay;

  /// Last representable instant of [lastDay]. Inclusive, and floored back to
  /// 23:59:59 where drift stores it, exactly like [MonthRange.end].
  DateTime get end =>
      DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59, 999, 999);

  /// Whether [date] falls in this week, whatever time of day it carries.
  bool contains(DateTime date) => !date.isBefore(start) && !date.isAfter(end);

  @override
  String toString() => 'WeekSpan($start..$lastDay)';
}

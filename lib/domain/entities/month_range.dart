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

  @override
  String toString() => 'MonthRange($year-${month.toString().padLeft(2, '0')})';
}

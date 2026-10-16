// Locks in the `DateTime` behaviour the month selector in `BackupPage`
// depends on, so a future "fix" that adds manual year wraparound handling
// cannot silently change what stepping one month means.

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('month selector arithmetic', () {
    test('day defaults to the 1st, so stepping never runs past month end', () {
      expect(DateTime(2026, 5), DateTime(2026, 5, 1));
    });

    test('month 0 rolls back to December of the previous year', () {
      expect(DateTime(2026, 0, 1), DateTime(2025, 12, 1));
    });

    test('month 13 rolls forward to January of the next year', () {
      expect(DateTime(2026, 13, 1), DateTime(2027, 1, 1));
    });

    test('stepping back from January lands on the previous December', () {
      final DateTime january = DateTime(2026, 1, 1);

      expect(
        DateTime(january.year, january.month - 1, 1),
        DateTime(2025, 12, 1),
      );
    });

    test('stepping forward from December lands on the next January', () {
      final DateTime december = DateTime(2025, 12, 1);

      expect(
        DateTime(december.year, december.month + 1, 1),
        DateTime(2026, 1, 1),
      );
    });
  });
}

// The harness behind every test that needs a real SQLite.
//
// `flutter test` runs on the Dart VM, so the library that gets opened is the host's:
// `sqlite3.dll` and then `winsqlite3.dll` on Windows, a system `libsqlite3` on Linux.
// The app ships its own copy through `sqlite3_flutter_libs`, which a host test cannot
// reach, so these tests run against a different build of SQLite — and that is fine,
// because what they pin is drift's own conversions and SQLite's own comparisons,
// neither of which is implementation-specific.
//
// A host with no library to open is reported as skipped rather than failed: that is a
// property of the machine, not a statement about the app. It is reported, not hidden.

import 'package:drift/native.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `DynamicLibrary.open` puts in the message when it cannot find a library.
///
/// Only an `ArgumentError` carrying this marker is treated as "this host has no
/// SQLite". Anything else escaping the open — a schema problem, a migration bug — is
/// rethrown, so a broken database cannot turn into a quiet skip.
const String _missingLibraryMarker = 'Failed to load dynamic library';

/// The real schema on an in-memory database, or `null` after marking the test skipped.
///
/// `return null` means the caller must stop; the skip has already been recorded.
AppDatabase? _openOrSkip() {
  try {
    return AppDatabase.withExecutor(NativeDatabase.memory());
  } on ArgumentError catch (error) {
    if (!'${error.message}'.contains(_missingLibraryMarker)) rethrow;
    markTestSkipped('no SQLite for `flutter test` to load on this host '
        '(the app ships its own; host tests use the system one): $error');
    return null;
  }
}

/// Runs [body] against a real in-memory database and closes it again.
void sqliteTest(
  String description,
  Future<void> Function(AppDatabase db) body,
) {
  test(description, () async {
    final AppDatabase? db = _openOrSkip();
    if (db == null) return;

    try {
      await body(db);
    } finally {
      await db.close();
    }
  });
}

/// The same as [sqliteTest], for a test that also needs to drive widgets.
void sqliteWidgetTest(
  String description,
  Future<void> Function(AppDatabase db, WidgetTester tester) body,
) {
  testWidgets(description, (WidgetTester tester) async {
    final AppDatabase? db = _openOrSkip();
    if (db == null) return;

    try {
      await body(db, tester);
    } finally {
      await db.close();
    }
  });
}

// Native SQLite connection. Imported only when `dart.library.io` is available;
// the web build uses `database_connection_web.dart` instead.
//
// Keeping `drift/native.dart` out of the web graph matters: it imports
// `dart:ffi`, which the web compiler rejects outright. `dart:io` by itself is
// fine on web (it compiles to stubs), but `dart:ffi` is not.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

LazyDatabase openConnection() {
  return LazyDatabase(() async {
    final Directory dbFolder = await getApplicationDocumentsDirectory();
    final File file = File(p.join(dbFolder.path, 'expense_tracker.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

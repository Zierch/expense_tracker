// The web never opens a local Drift database — its rows live in Supabase.
//
// `AppDatabase()` still has to compile on web because the shared provider file
// mentions the type. This stub keeps `drift/native.dart` (and with it
// `dart:ffi`) out of the web build. Reaching it would be a wiring bug, so it
// fails loudly rather than pretending to have an offline store.

import 'package:drift/drift.dart';

LazyDatabase openConnection() => LazyDatabase(() async {
      throw StateError(
        'The web build uses Supabase, not the local SQLite database.',
      );
    });

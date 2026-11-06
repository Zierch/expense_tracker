import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/presentation/pages/backup_page.dart';
import 'package:expense_tracker/presentation/providers/backup_providers.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';

import 'sqlite_support.dart';

void main() {
  sqliteWidgetTest(
    'Settings page renders visual redesign sections with disabled full snapshot/sync buttons',
    (AppDatabase db, WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          googleAccountProvider.overrideWith(
            (Ref ref) => Stream<GoogleSignInAccount?>.value(null),
          ),
        ],
        child: const MaterialApp(home: BackupPage()),
      ));

      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Title
      expect(find.text('Settings'), findsOneWidget);

      // Section 1: Appearance
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);

      // Section 2: Google Drive Account (signed out)
      expect(find.text('Backup to Google Drive'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in with Google'), findsOneWidget);
      expect(find.text('Limited access'), findsOneWidget);

      expect(find.text('Backup & Sync'), findsOneWidget);
      expect(find.text('Sign in with Google to back up or sync.'), findsOneWidget);
      expect(find.text('Connect Google Drive'), findsOneWidget);
      expect(find.text('Import a backup'), findsNothing);

      // Section 5: App updates
      expect(find.text('App updates'), findsOneWidget);

      // Cleanup
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  sqliteWidgetTest(
    'Settings theme dialog opens and presents system, light, and dark options',
    (AppDatabase db, WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          googleAccountProvider.overrideWith(
            (Ref ref) => Stream<GoogleSignInAccount?>.value(null),
          ),
        ],
        child: const MaterialApp(home: BackupPage()),
      ));

      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();

      expect(find.text('Follow the system'), findsWidgets);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
}

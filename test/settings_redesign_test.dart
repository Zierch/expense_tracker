import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/transaction_repository_impl.dart';
import 'package:expense_tracker/domain/usecases/import_month_usecase.dart';
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
          importMonthUseCaseProvider.overrideWithValue(
            ImportMonthUseCase(TransactionRepositoryImpl(db)),
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

      // Section 3: Backup & Sync (Full Snapshot Preview)
      expect(find.text('Backup & Sync'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.textContaining('Full snapshot backup and sync are currently unavailable'), findsOneWidget);

      // Snapshot & sync buttons must exist and be disabled
      final Finder backupAllFinder = find.widgetWithText(FilledButton, 'Back up all data');
      final Finder syncLatestFinder = find.widgetWithText(OutlinedButton, 'Sync latest backup');
      expect(backupAllFinder, findsOneWidget);
      expect(syncLatestFinder, findsOneWidget);

      final FilledButton backupAllBtn = tester.widget<FilledButton>(backupAllFinder);
      expect(backupAllBtn.onPressed, isNull, reason: 'Full snapshot backup must be disabled');

      final OutlinedButton syncLatestBtn = tester.widget<OutlinedButton>(syncLatestFinder);
      expect(syncLatestBtn.onPressed, isNull, reason: 'Full snapshot sync must be disabled');

      // Section 4: Import a backup (legacy functional card preserved)
      expect(find.text('Import a backup'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Choose a backup file'), findsOneWidget);

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

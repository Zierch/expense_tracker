// The update pop-up offers one button that moves the app somewhere, and the
// somewhere it moves to is a tab.
//
// The Settings screen is the third branch of the shell — the one the bottom bar
// draws its third icon for. Pushing it as an ordinary page on top of the shell
// shows Settings while the bar still says Home, which is a small lie the user
// has to reconcile: the highlighted tab is where the app claims to be. The
// press therefore has to move the shell, not cover it.

import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/services/app_update_service.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/presentation/pages/backup_page.dart';
import 'package:expense_tracker/presentation/providers/backup_providers.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/providers/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'sqlite_support.dart';

/// Stands in for the controller so the pop-up appears without a network call.
///
/// Only the state is faked: the listener, the dialog and the navigation it
/// triggers are the real ones, which is the whole point — a fake that also
/// answered the button would be testing itself.
class _UpdateWaiting extends AppUpdateController {
  @override
  AppUpdateState build() => const UpdateIdle();

  /// The real launch check, without the network: it starts idle and then finds
  /// a release, which is the transition the pop-up listens for.
  @override
  Future<void> checkOnLaunch() async {
    state = UpdateAvailable(_release);
  }
}

final RemoteRelease _release = RemoteRelease(
  version: '1.11.0',
  tagName: 'v1.11.0',
  downloadUrl: Uri.parse('https://example.invalid/app.apk'),
  sizeInBytes: 1,
  publishedSha256: null,
);

/// The tab the bottom bar is showing as selected.
int _selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  sqliteWidgetTest(
    'Review moves to the Settings tab instead of covering the shell',
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
          appUpdateControllerProvider.overrideWith(_UpdateWaiting.new),
        ],
        child: const ExpenseTrackerApp(),
      ));
      // The launch check runs in a post-frame callback and the dialog is shown
      // from a listener, so the first frame alone does not have it.
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(_selectedTab(tester), 0, reason: 'the app opens on Home');

      await tester.tap(find.widgetWithText(FilledButton, 'Review'));
      await tester.pumpAndSettle();

      expect(find.byType(BackupPage), findsOneWidget);
      expect(_selectedTab(tester), 2,
          reason: 'the bar has to agree with the page: Settings is the third '
              'tab, and a pushed page would leave the bar on Home');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
}

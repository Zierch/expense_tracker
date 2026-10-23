import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expense_tracker/presentation/pages/home_page.dart';
import 'package:expense_tracker/presentation/pages/add_transaction_page.dart';
import 'package:expense_tracker/presentation/pages/recurring_page.dart';
import 'package:expense_tracker/presentation/pages/statistics_page.dart';
import 'package:expense_tracker/presentation/pages/backup_page.dart';
import 'package:expense_tracker/presentation/providers/theme_provider.dart';
import 'package:expense_tracker/presentation/providers/update_providers.dart';
import 'package:expense_tracker/data/services/app_update_service.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The backdrop the pages paint, shared with the system bars: the navigation bar
/// has to look like the page behind it, not like a strip of another app.
const Color _darkBackground = Color(0xFF0E1113);
const Color _lightBackground = Color(0xFFF4F6F8);

/// The system bars in the app's own brightness.
///
/// The theme is the user's choice, so it need not match the device's: a light
/// system under an in-app dark theme left the navigation bar white, a strip of
/// another app below the dashboard. The bars therefore follow this app's
/// brightness rather than the Android theme's.
///
/// `SystemUiOverlayStyle.light` and `.dark` name their *icons*, not their
/// background — `.light` is light icons, for a dark backdrop — which is the
/// opposite of how the names read.
///
/// Android 15 and newer ignore [SystemUiOverlayStyle.systemNavigationBarColor]
/// for an app targeting 35 or higher: the bar is made transparent and the system
/// lays a *contrast scrim* over it, 80% white or 80% black, depending on which
/// way it believes the app points. On a Xiaomi on Android 16 it believed "light"
/// under an in-app dark theme and the dark bar came out `#CFCFD0` — this app's
/// colour with white painted over it. The colour below is therefore only a hint
/// for older Androids; the scrim itself is switched off in the four Android
/// themes under `android/app/src/main/res/` (`enforceNavigationBarContrast`),
/// which is what leaves the bar transparent for the page to show through.
SystemUiOverlayStyle systemUiStyleFor(Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;
  return (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
      .copyWith(
    systemNavigationBarColor: isDark ? _darkBackground : _lightBackground,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
  );
}

/// Root navigator key, so background code (the update pop-up) can reach the
/// navigator that every page of the app lives under.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/add',
        builder: (context, state) => const AddTransactionPage(),
      ),
      GoRoute(
        path: '/edit/:id',
        builder: (context, state) => AddTransactionPage(
          transactionId: int.tryParse(state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/statistics',
        builder: (context, state) => const StatisticsPage(),
      ),
      GoRoute(
        path: '/recurring',
        builder: (context, state) => const RecurringPage(),
      ),
      GoRoute(
        path: '/backup',
        builder: (context, state) => const BackupPage(),
      ),
    ],
  );
});

Future<void> main() async {
  // The theme choice is loaded before runApp, so the first frame carries the
  // remembered mode rather than flashing the system theme while prefs load.
  // A failure must not strand the app on the splash — v1.2.0 taught that in
  // production — so the provider stays unoverridden (null = no memory of a
  // theme choice) and the app opens on the system theme instead.
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } on Object catch (error) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      library: 'expense_tracker',
      context: ErrorDescription('loading preferences on startup'),
    ));
  }

  runApp(ProviderScope(
    overrides: prefs == null
        ? const <Override>[]
        : <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const ExpenseTrackerApp(),
  ));
}

class ExpenseTrackerApp extends ConsumerStatefulWidget {
  const ExpenseTrackerApp({super.key});

  @override
  ConsumerState<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends ConsumerState<ExpenseTrackerApp> {
  bool _updateDialogOpen = false;

  @override
  void initState() {
    super.initState();
    // The launch check lives entirely in the background: once the app has
    // drawn its first frame, the request runs out from under the UI and only
    // ever *pops up* when a newer release actually exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(appUpdateControllerProvider.notifier).checkOnLaunch());
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // The pop-up at the root so it can appear on any page. Exactly once per
    // launch and only for a *newly* discovered update: reopening it on every
    // rebuild would turn an offer into a nag.
    ref.listen<AppUpdateState>(appUpdateControllerProvider, (previous, next) {
      if (next is! UpdateAvailable || previous is UpdateAvailable) return;
      if (!mounted || _updateDialogOpen) return;
      _updateDialogOpen = true;
      unawaited(_showUpdatePopUp(next.release));
    });

    return MaterialApp.router(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      // The system bars belong to the window, not to the widget tree, so nothing
      // repaints them when the theme changes. Reaching them from here covers
      // every page, including any that shows no app bar.
      builder: (BuildContext context, Widget? child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemUiStyleFor(Theme.of(context).brightness),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  /// The update pop-up: one offer, two answers, data untouched either way.
  ///
  /// Shown against the root navigator, not this widget's context: the listener
  /// lives above `MaterialApp`, where no navigator exists to look up — the
  /// global key is the bridge into the navigator every page lives under.
  Future<void> _showUpdatePopUp(RemoteRelease release) async {
    final NavigatorState? navigator = rootNavigatorKey.currentState;

    if (navigator == null) return;
    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.system_update_outlined),
        title: const Text('Update available'),
        content: Text(
          'Expense Tracker ${release.version} is ready to download from the '
          'Releases page. Your data and your Google Drive sign-in are kept.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(routerProvider).push('/backup');
            },
            child: const Text('Review'),
          ),
        ],
      ),
    );
    // Either answer is final for this launch; a rebuild may not re-open it.
    _updateDialogOpen = false;
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: isDark ? const Color(0xFF36C79B) : const Color(0xFF00897B),
      brightness: brightness,
    ).copyWith(
      surface: isDark ? const Color(0xFF15181B) : const Color(0xFFFFFFFF),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? _darkBackground : _lightBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? _darkBackground : _lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: isDark ? const Color(0xFF1A1E22) : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? const Color(0xFF2A3036) : const Color(0xFFE7EAED),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF2A3036) : const Color(0xFFE7EAED),
        space: 1,
        thickness: 1,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w600),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1A1E22) : const Color(0xFFFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF2A3036) : const Color(0xFFD9DEE3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF2A3036) : const Color(0xFFD9DEE3),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:expense_tracker/presentation/pages/splash_page.dart';
import 'package:expense_tracker/presentation/pages/login_page.dart';
import 'package:expense_tracker/presentation/pages/web_settings_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expense_tracker/presentation/pages/home_page.dart';
import 'package:expense_tracker/presentation/pages/add_transaction_page.dart';
import 'package:expense_tracker/presentation/pages/statistics_page.dart';
import 'package:expense_tracker/presentation/pages/backup_page.dart';
import 'package:expense_tracker/presentation/providers/theme_provider.dart';
import 'package:expense_tracker/presentation/theme/web_desktop_style.dart';
import 'package:expense_tracker/presentation/providers/update_providers.dart';
import 'package:expense_tracker/data/services/app_update_service.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The backdrop the pages paint, shared with the system bars: the navigation bar
/// has to look like the page behind it, not like a strip of another app.
const Color _darkBackground = Color(0xFF101916);
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
    // Android has no account and must keep opening on the dashboard. On web an
    // unauthenticated visit goes to /login whether it starts there or deep-links
    // into /statistics or /edit/1.
    redirect: (BuildContext context, GoRouterState state) {
      if (!kIsWeb) return null;
      final bool signedIn = Supabase.instance.client.auth.currentSession != null;
      final bool onLogin = state.matchedLocation == '/login';
      if (!signedIn && !onLogin) return '/login';
      if (signedIn && onLogin) return '/';
      return null;
    },
    routes: [
      if (kIsWeb)
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        // A phone gets the bottom bar. A wide web window gets a side rail and
        // a centred content column: stretching the phone layout across a
        // 1920px monitor made every card enormous. Android always takes the
        // first branch, unchanged.
        builder: (context, state, shell) => LayoutBuilder(
          builder: (BuildContext context, BoxConstraints size) {
            final bool wide = kIsWeb && size.maxWidth >= 1000;
            if (!wide) {
              return Scaffold(
                body: shell,
                bottomNavigationBar: NavigationBar(
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: (index) => shell.goBranch(
                    index,
                    initialLocation: index == shell.currentIndex,
                  ),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                    NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Statistics'),
                    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
                  ],
                ),
              );
            }
            return Scaffold(
              body: Row(
                children: <Widget>[
                  WebSidebar(
                    selectedIndex: shell.currentIndex,
                    onSelected: (index) => shell.goBranch(
                      index,
                      initialLocation: index == shell.currentIndex,
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: shell,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (context, state) => const HomePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/statistics', builder: (context, state) => const StatisticsPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/backup',
              builder: (context, state) => kIsWeb
                  ? const WebSettingsPage()
                  : const BackupPage(),
            ),
          ]),
        ],
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

  // Web gets its data from Supabase, so it is the only platform that needs the
  // client. The values come from `--dart-define` at build time; the anon key is
  // public by design and RLS, not secrecy, is what limits access. Android never
  // reads either value and stays entirely offline.
  if (kIsWeb) {
    const String url = String.fromEnvironment('SUPABASE_URL');
    const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isEmpty || anonKey.isEmpty) {
      throw StateError(
        'Web builds need SUPABASE_URL and SUPABASE_ANON_KEY from --dart-define.',
      );
    }
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

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
    child: const ExpenseTrackerApp(showSplash: true),
  ));
}

class ExpenseTrackerApp extends ConsumerStatefulWidget {
  const ExpenseTrackerApp({super.key, this.showSplash = false});

  final bool showSplash;

  @override
  ConsumerState<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends ConsumerState<ExpenseTrackerApp> {
  bool _updateDialogOpen = false;
  late bool _showSplash = widget.showSplash;
  Timer? _splashTimer;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    if (_showSplash) {
      _splashTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _showSplash = false);
      });
    }
    // The launch check lives entirely in the background: once the app has
    // drawn its first frame, the request runs out from under the UI and only
    // ever *pops up* when a newer release actually exists.
    // The update check talks to Android's installer through a MethodChannel.
    // Vercel deploys the web build, so there is nothing for it to check there.
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          ref.read(appUpdateControllerProvider.notifier).checkOnLaunch(),
        );
      });
    }

    // GoRouter's redirect only runs on navigation. A session that expires or
    // is revoked while the user sits on a page would otherwise leave them on
    // a screen of failed reads, so send them to the sign-in page immediately.
    // Owned by the State so a hot restart or a test that creates two apps does
    // not leave an older listener behind.
    if (kIsWeb) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((data) {
        if (data.event != AuthChangeEvent.signedOut) return;
        final BuildContext? context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          GoRouter.of(context).go('/login');
        }
      });
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
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
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (_showSplash) const Positioned.fill(child: SplashPage()),
            ],
          ),
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
              // `go`, not `push`: Settings is the shell's third branch, so
              // going to it moves the bottom bar with the page. Pushing drew
              // the same page on top of the shell and left the bar on Home —
              // the tab and the screen disagreed about where the user was.
              ref.read(routerProvider).go('/backup');
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
    // The FigCraft mockup is a dark navy desktop shell. It is web-only: the
    // Android build keeps the green palette below, byte for byte.
    if (kIsWeb && isDark) return _buildWebDesktopTheme();

    final scheme = ColorScheme.fromSeed(
      seedColor: isDark ? const Color(0xFF83DFB7) : const Color(0xFF0E5A44),
      brightness: brightness,
    ).copyWith(
      surface: isDark ? const Color(0xFF1B2924) : const Color(0xFFFFFFFF),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
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
        color: isDark ? const Color(0xFF1B2924) : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? const Color(0xFF31443A) : const Color(0xFFE7EAED),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF31443A) : const Color(0xFFE7EAED),
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
            color: isDark ? const Color(0xFF31443A) : const Color(0xFFD9DEE3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF31443A) : const Color(0xFFD9DEE3),
          ),
        ),
      ),
    );
  }

  ThemeData _buildWebDesktopTheme() {
    const Color background = WebDesktopStyle.background;
    const Color card = WebDesktopStyle.card;
    const Color muted = WebDesktopStyle.muted;
    const ColorScheme scheme = ColorScheme.dark(
      primary: WebDesktopStyle.accent,
      onPrimary: WebDesktopStyle.text,
      secondary: WebDesktopStyle.positive,
      surface: card,
      onSurface: WebDesktopStyle.text,
      outline: muted,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF25324A),
        space: 1,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: WebDesktopStyle.accent,
          foregroundColor: WebDesktopStyle.text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: WebDesktopStyle.text,
          side: const BorderSide(color: muted),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

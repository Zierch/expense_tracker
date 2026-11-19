// Web platform port contract validation.
//
// The web port adds Supabase backend selected via kIsWeb at provider level,
// with conditional imports keeping Drift out of the web build. These tests
// lock in structural decisions that a refactor could silently break:
//
// - Supabase repo must replicate Drift import logic (alias handling, user's
//   own subcategory name wins over app default rename).
// - Query methods must embed categories/subcategories via select join, or
//   _toEntity crashes reading null.
// - Conditional imports must keep dart:io and dart:ffi out of web build.
// - Deploy workflow must never leak service_role key or Android signing material.
//
// Read source files as strings and assert contracts hold.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Supabase repository contract', () {
    test('import logic must check user\'s own subcategory name before applying alias', () {
      final String repo = File('lib/data/repositories/supabase_transaction_repository.dart')
          .readAsStringSync();

      // Drift version (transaction_repository_impl.dart line 158-164) checks:
      // if file says "Pocket Money" and user has their own "Pocket Money",
      // use that (not alias to "Allowance"). Without this check, import
      // mis-attributes transactions for users who created their own subcategory
      // matching an old default name.
      //
      // Supabase must replicate: call resolveImportedSubcategoryName, then
      // check if file's original name exists locally (query subcategories table
      // .eq('name', originalName)), return original name if found, else alias.
      expect(
        repo,
        contains('_importName'),
        reason:
            'MISSING: Supabase repo must have _importName helper (or equivalent) '
            'that checks user\'s own subcategory name before applying alias. '
            'Without this, importing a v1.10.x backup (names "Pocket Money") '
            'when user has their own "Pocket Money" subcategory mis-attributes '
            'transactions to "Allowance" instead. See transaction_repository_impl.dart '
            'line 158-164 for Drift version that must be replicated.',
      );

      expect(
        repo,
        contains('resolveImportedSubcategoryName'),
        reason:
            'MISSING: Supabase repo must call resolveImportedSubcategoryName '
            '(from subcategory_aliases.dart) to apply "Pocket Money" → "Allowance" '
            'alias during import, same as Drift.',
      );

      // The check itself: query subcategories WHERE name = originalName
      expect(
        repo,
        matches(RegExp(
          r"\.from\(.subcategories.\).*\.eq\(.name.,\s*\w+\)",
          dotAll: true,
        )),
        reason:
            'MISSING: Supabase repo must query subcategories table to check if '
            'file\'s original subcategory name exists locally (user\'s own data) '
            'before applying alias. Pattern: .from(\'subcategories\').eq(\'name\', originalName). '
            'This is what makes user\'s "Pocket Money" win over alias to "Allowance".',
      );
    });

    test('query methods must embed categories/subcategories via select join', () {
      final String repo = File('lib/data/repositories/supabase_transaction_repository.dart')
          .readAsStringSync();

      // _toEntity (line 85-98) reads row['categories']['name'] and
      // row['subcategories']['name']. Supabase doesn't auto-embed FKs — you
      // must request them in .select(). Without join, row['categories'] is null,
      // _toEntity crashes or returns null categoryName (every transaction shows
      // "Uncategorized" on home page). BLOCKER: app unusable on web.
      //
      // Fix: .select('*, categories!inner(name), subcategories(name)')
      // Must appear in: _orderedRows (getAllTransactions, watchAllTransactions)
      // and getTransactionsByDateRange.
      expect(
        repo,
        contains('categories!inner(name)'),
        reason:
            'BLOCKER: Supabase queries must embed categories via '
            '.select(\'*, categories!inner(name), subcategories(name)\'). '
            'Without this, _toEntity reads row[\'categories\'] = null and crashes '
            'or shows "Uncategorized" for every transaction. getAllTransactions, '
            'watchAllTransactions, getTransactionsByDateRange all broken. '
            'Pattern already correct in _byCategory (line 204), copy to other queries.',
      );

      expect(
        repo,
        contains('subcategories(name)'),
        reason:
            'BLOCKER: Supabase queries must embed subcategories via '
            '.select(\'*, categories!inner(name), subcategories(name)\'). '
            'Left outer join (nullable FK). Without this, subcategoryName always null.',
      );

      // Should appear at least twice: _orderedRows + getTransactionsByDateRange
      final int categoriesJoinCount =
          'categories!inner(name)'.allMatches(repo).length;
      expect(
        categoriesJoinCount,
        greaterThanOrEqualTo(2),
        reason:
            'BLOCKER: categories!inner(name) must appear at least twice: '
            'once in _orderedRows (getAllTransactions, watchAllTransactions) '
            'and once in getTransactionsByDateRange. Found only $categoriesJoinCount. '
            'All read operations must embed categories or _toEntity crashes.',
      );
    });

    test('seed subcategories must include Allowance (not Pocket Money) per v1.11.0', () {
      final String repo = File('lib/data/repositories/supabase_transaction_repository.dart')
          .readAsStringSync();

      // v1.11.0 renamed "Pocket Money" back to "Allowance" (v1.10.0 renamed it
      // the other way, v1.11.0 restored). Seed must use Allowance. Import applies
      // alias ("Pocket Money" → "Allowance") so old backups match seed.
      expect(
        repo,
        contains("('Allowance', 'income')"),
        reason:
            'MISSING: _defaultSubcategories must include (\'Allowance\', \'income\') '
            'per v1.11.0. Drift seed ships Allowance (not Pocket Money), web must match. '
            'Import alias resolves "Pocket Money" → "Allowance" for v1.10.x backups.',
      );

      expect(
        repo,
        isNot(contains("'Pocket Money'")),
        reason:
            'FORBIDDEN: _defaultSubcategories must NOT include \'Pocket Money\'. '
            'That name was retired in v1.11.0. Seed must use "Allowance" instead. '
            'Old backups reference "Pocket Money" and import applies alias to "Allowance".',
      );

      // Should have 10 subcategories total: 5 income + 5 expense
      // (Salary, Freelance, Bonus, Gift, Allowance, Food, Other Needs,
      // Data/Internet Package, Coffee Shop, Fuel)
      final int subcategoryCount = RegExp(r"\('\w+[^']*', 'income|expense'\)")
          .allMatches(repo)
          .length;
      expect(
        subcategoryCount,
        equals(10),
        reason:
            'MISSING: _defaultSubcategories must have exactly 10 entries (5 income, '
            '5 expense). Drift seed ships these 10, web must match. Found $subcategoryCount.',
      );
    });

    test('entity id must be cast directly from bigint (no hashCode mapping)', () {
      final String repo = File('lib/data/repositories/supabase_transaction_repository.dart')
          .readAsStringSync();

      // Schema uses bigint identity (not uuid), so TransactionEntity.id stays int.
      // Direct cast: id: row['id'] as int. NO hashCode (that was uuid fallback).
      // hashCode collision would make edit/delete target wrong row (critical bug).
      expect(
        repo,
        isNot(contains('hashCode')),
        reason:
            'FORBIDDEN: Supabase repo must NOT use hashCode for entity id mapping. '
            'Schema uses bigint identity (not uuid), so id: row[\'id\'] as int is direct. '
            'hashCode was the uuid fallback (collision risk), but schema chose bigint '
            'precisely to avoid that. If hashCode appears, schema/entity mapping diverged.',
      );

      // Should have direct cast: row['id'] as int
      expect(
        repo,
        matches(RegExp(r"row\[.id.\]\s+as\s+int")),
        reason:
            'MISSING: _toEntity must cast id directly: row[\'id\'] as int. '
            'Schema uses bigint identity, TransactionEntity.id is int, no mapping needed. '
            'If this fails, check if hashCode was introduced (wrong) or cast was removed.',
      );
    });
  });

  group('main.dart web initialization and routing', () {
    test('Supabase.initialize must be guarded by if (kIsWeb)', () {
      final String main = File('lib/main.dart').readAsStringSync();

      // Android never calls Supabase.initialize (offline Drift). Web needs it
      // before ProviderScope (client used in transactionRepositoryProvider).
      // Must be inside if (kIsWeb) block, not at top level (Android build would fail).
      expect(
        main,
        contains('if (kIsWeb)'),
        reason:
            'MISSING: main.dart must have if (kIsWeb) guard. Supabase.initialize '
            'must be inside it (Android stays offline Drift, web uses Supabase). '
            'If this fails, kIsWeb check was removed or renamed.',
      );

      // Supabase.initialize must come after if (kIsWeb)
      final int kIsWebPos = main.indexOf('if (kIsWeb)');
      final int supabaseInitPos = main.indexOf('Supabase.initialize');

      expect(
        kIsWebPos,
        greaterThan(0),
        reason: 'if (kIsWeb) not found in main.dart',
      );

      expect(
        supabaseInitPos,
        greaterThan(kIsWebPos),
        reason:
            'WRONG ORDER: Supabase.initialize must come AFTER if (kIsWeb) guard. '
            'If initialize is before guard or at top level, Android build fails '
            '(Supabase dependency not available). Current order: if(kIsWeb) at $kIsWebPos, '
            'initialize at $supabaseInitPos.',
      );

      expect(
        main,
        stringContainsInOrder([
          'if (kIsWeb)',
          'SUPABASE_URL',
          'SUPABASE_ANON_KEY',
          'Supabase.initialize',
        ]),
        reason:
            'MISSING: main.dart must initialize Supabase inside if(kIsWeb) block, '
            'reading URL and anon key from dart-define (String.fromEnvironment). '
            'Pattern: if(kIsWeb) { const url = String.fromEnvironment(\'SUPABASE_URL\'); '
            '... await Supabase.initialize(url: url, anonKey: anonKey); }',
      );
    });

    test('appUpdateControllerProvider.checkOnLaunch must be guarded by if (!kIsWeb)', () {
      final String main = File('lib/main.dart').readAsStringSync();

      // appUpdateControllerProvider calls MethodChannel (app.updates), which
      // throws MissingPluginException on web. Must be guarded if (!kIsWeb).
      // Web deploys via Vercel (no APK, no update check).
      expect(
        main,
        contains('checkOnLaunch'),
        reason:
            'MISSING: main.dart must call appUpdateControllerProvider.notifier.checkOnLaunch() '
            'for Android update check. If this is gone, update feature was removed.',
      );

      final int notKIsWebPos = main.indexOf('if (!kIsWeb)');
      final int checkOnLaunchPos = main.indexOf('checkOnLaunch');

      expect(
        notKIsWebPos,
        greaterThan(0),
        reason:
            'MISSING: main.dart must have if (!kIsWeb) guard for checkOnLaunch(). '
            'Without this, web build crashes calling MethodChannel.',
      );

      expect(
        checkOnLaunchPos,
        greaterThan(notKIsWebPos),
        reason:
            'WRONG ORDER: checkOnLaunch() must be AFTER if (!kIsWeb) guard. '
            'If checkOnLaunch comes before guard or at top level, web build crashes '
            'with MissingPluginException (MethodChannel app.updates unavailable). '
            'Current order: if(!kIsWeb) at $notKIsWebPos, checkOnLaunch at $checkOnLaunchPos.',
      );
    });

    test('GoRouter must have /login route for web authentication', () {
      final String main = File('lib/main.dart').readAsStringSync();

      // Web requires auth (Supabase), Android is offline (no auth). /login route
      // must exist, outside StatefulShellRoute (no bottom nav on login page).
      expect(
        main,
        contains("GoRoute(path: '/login'"),
        reason:
            'MISSING: GoRouter must define GoRoute(path: \'/login\') for web. '
            'Android skips it (offline, no auth), but web unauthenticated users '
            'must be redirected to /login. If this is gone, login flow broken.',
      );

      expect(
        main,
        contains('LoginPage'),
        reason:
            'MISSING: /login route must build LoginPage(). If this is gone, '
            'login UI missing (web users cannot sign in).',
      );
    });

    test('GoRouter redirect must send unauthenticated web users to /login', () {
      final String main = File('lib/main.dart').readAsStringSync();

      // redirect: (context, state) { if (!kIsWeb) return null; ... if (!signedIn && !onLogin) return '/login'; }
      // Web unauthenticated → /login. Android skips redirect (no auth).
      expect(
        main,
        contains('redirect:'),
        reason:
            'MISSING: GoRouter must have redirect callback. Web needs it to send '
            'unauthenticated users to /login. If this is gone, deep links work '
            'unauthenticated (security hole).',
      );

      expect(
        main,
        stringContainsInOrder([
          'redirect:',
          'if (!kIsWeb) return null',
          "return '/login'",
        ]),
        reason:
            'MISSING: GoRouter redirect must check if(!kIsWeb) return null (Android '
            'skips auth), then return \'/login\' for unauthenticated web users. '
            'Pattern: redirect: (context, state) { if(!kIsWeb) return null; '
            'final signedIn = Supabase.instance.client.auth.currentSession != null; '
            'if(!signedIn && !onLogin) return \'/login\'; return null; }',
      );
    });
  });

  group('providers.dart repository selection', () {
    test('transactionRepositoryProvider must select SupabaseTransactionRepository on web', () {
      final String providers = File('lib/presentation/providers/providers.dart')
          .readAsStringSync();

      // Single boundary: if (kIsWeb) SupabaseTransactionRepository, else
      // TransactionRepositoryImpl(databaseProvider). Domain unchanged.
      expect(
        providers,
        contains('if (kIsWeb)'),
        reason:
            'MISSING: providers.dart must have if(kIsWeb) in transactionRepositoryProvider. '
            'This is the platform selection boundary: web → Supabase, Android → Drift. '
            'If this is gone, both platforms use same backend (wrong).',
      );

      expect(
        providers,
        contains('SupabaseTransactionRepository'),
        reason:
            'MISSING: transactionRepositoryProvider must return '
            'SupabaseTransactionRepository on web. If this is gone, web backend missing.',
      );

      expect(
        providers,
        stringContainsInOrder([
          'transactionRepository',
          'if (kIsWeb)',
          'SupabaseTransactionRepository',
          'TransactionRepositoryImpl',
        ]),
        reason:
            'WRONG ORDER: transactionRepositoryProvider must select '
            'SupabaseTransactionRepository when kIsWeb, else TransactionRepositoryImpl. '
            'Pattern: @riverpod TransactionRepository transactionRepository(Ref ref) { '
            'if(kIsWeb) return SupabaseTransactionRepository(...); '
            'return TransactionRepositoryImpl(ref.watch(databaseProvider)); }',
      );
    });
  });

  group('app_database.dart conditional import', () {
    test('must NOT import dart:io, path_provider, or drift/native.dart directly', () {
      final String appDatabase = File('lib/data/database/app_database.dart')
          .readAsStringSync();

      // Drift imports dart:ffi (via drift/native.dart), which web cannot compile.
      // Conditional import keeps it out: database_connection_io.dart if dart.library.html
      // database_connection_web.dart. app_database.dart itself must NOT import dart:io
      // or path_provider directly (those are in database_connection_io.dart only).
      expect(
        appDatabase,
        isNot(matches(RegExp(r"import\s+.dart:io."))),
        reason:
            'FORBIDDEN: app_database.dart must NOT import dart:io directly. '
            'That import must be in database_connection_io.dart only (conditional). '
            'If dart:io appears here, web build may fail or bloat (tree-shaking broken).',
      );

      expect(
        appDatabase,
        isNot(contains("import 'package:path_provider")),
        reason:
            'FORBIDDEN: app_database.dart must NOT import path_provider directly. '
            'That import must be in database_connection_io.dart only (conditional). '
            'If path_provider appears here, web build may fail or bloat.',
      );

      expect(
        appDatabase,
        isNot(contains("import 'package:drift/native.dart")),
        reason:
            'FORBIDDEN: app_database.dart must NOT import drift/native.dart directly. '
            'That import pulls in dart:ffi, which web cannot compile. It must be in '
            'database_connection_io.dart only (conditional).',
      );
    });

    test('must use conditional import for database connection', () {
      final String appDatabase = File('lib/data/database/app_database.dart')
          .readAsStringSync();

      // Pattern: import 'database_connection_io.dart' if (dart.library.html) 'database_connection_web.dart';
      expect(
        appDatabase,
        matches(RegExp(
          r"import\s+.database_connection_io\.dart."
          r"\s+if\s+\(dart\.library\.html\)\s+.database_connection_web\.dart.",
        )),
        reason:
            'MISSING: app_database.dart must use conditional import: '
            'import \'database_connection_io.dart\' if (dart.library.html) '
            '\'database_connection_web.dart\';. This is what keeps dart:io and dart:ffi '
            'out of web build (database_connection_web.dart is stub, no native imports). '
            'If this pattern is gone, conditional import was removed (tree-shaking broken).',
      );
    });
  });

  group('vercel.json SPA rewrite', () {
    test('must rewrite all routes to index.html for client-side routing', () {
      final String vercelJson = File('vercel.json').readAsStringSync();
      final Map<String, dynamic> config = jsonDecode(vercelJson);

      // Flutter web is SPA: /statistics, /edit/1 are client routes. Without rewrite,
      // Vercel serves 404 on direct URL or refresh. Fix: rewrite /(.*) → /index.html,
      // Flutter router handles route.
      expect(
        config,
        contains('rewrites'),
        reason:
            'MISSING: vercel.json must have "rewrites" array. Without it, /statistics '
            'direct URL returns 404 (Vercel looks for statistics.html, not found). '
            'SPA needs all routes rewritten to /index.html.',
      );

      final List<dynamic>? rewrites = config['rewrites'];
      expect(
        rewrites,
        isNotNull,
        reason: 'vercel.json rewrites must not be null',
      );

      expect(
        rewrites,
        isNotEmpty,
        reason:
            'MISSING: vercel.json rewrites array is empty. Must have at least one '
            'rewrite: {"source": "/(.*)", "destination": "/index.html"}. Without this, '
            'direct URLs and refreshes return 404.',
      );

      // Check first rewrite has correct pattern
      final Map<String, dynamic> firstRewrite = rewrites!.first;
      expect(
        firstRewrite['source'],
        equals('/(.*)'),
        reason:
            'WRONG PATTERN: vercel.json rewrite source must be "/(.*)" (all paths). '
            'Found: ${firstRewrite['source']}. Without catch-all, some routes 404.',
      );

      expect(
        firstRewrite['destination'],
        equals('/index.html'),
        reason:
            'WRONG DESTINATION: vercel.json rewrite destination must be "/index.html". '
            'Found: ${firstRewrite['destination']}. This is where Vercel sends all requests '
            'so Flutter router can handle route.',
      );
    });
  });

  group('deploy-web.yml workflow security', () {
    test('must build with flutter build web and dart-define secrets', () {
      final String workflow = File('.github/workflows/deploy-web.yml')
          .readAsStringSync();

      // Web build needs --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
      // from GitHub Secrets. Values read in main.dart via String.fromEnvironment.
      expect(
        workflow,
        contains('flutter build web --release'),
        reason:
            'MISSING: deploy-web.yml must run flutter build web --release. '
            'If this is gone, web deploy broken (no artifact to upload).',
      );

      expect(
        workflow,
        contains('SUPABASE_URL'),
        reason:
            'MISSING: deploy-web.yml must reference SUPABASE_URL secret. '
            'Web build needs it via --dart-define. If this is gone, Supabase.initialize '
            'fails (no URL).',
      );

      expect(
        workflow,
        contains('SUPABASE_ANON_KEY'),
        reason:
            'MISSING: deploy-web.yml must reference SUPABASE_ANON_KEY secret. '
            'Web build needs it via --dart-define. If this is gone, Supabase.initialize '
            'fails (no anon key).',
      );

      expect(
        workflow,
        stringContainsInOrder([
          'flutter build web --release',
          '--dart-define=SUPABASE_URL',
          '--dart-define=SUPABASE_ANON_KEY',
        ]),
        reason:
            'WRONG ORDER: flutter build web must come with --dart-define for both '
            'SUPABASE_URL and SUPABASE_ANON_KEY. Pattern: '
            'flutter build web --release --dart-define=SUPABASE_URL="..." '
            '--dart-define=SUPABASE_ANON_KEY="...". Without both, initialize fails.',
      );
    });

    test('must deploy to Vercel with prod flag', () {
      final String workflow = File('.github/workflows/deploy-web.yml')
          .readAsStringSync();

      // Deploy via Vercel CLI: vercel deploy --prod. Workflow needs VERCEL_TOKEN,
      // VERCEL_ORG_ID, VERCEL_PROJECT_ID secrets.
      expect(
        workflow,
        contains('vercel deploy --prod'),
        reason:
            'MISSING: deploy-web.yml must run vercel deploy --prod. '
            'If this is gone, deploy step missing (build succeeds but not published).',
      );

      expect(
        workflow,
        contains('VERCEL_TOKEN'),
        reason:
            'MISSING: deploy-web.yml must reference VERCEL_TOKEN secret. '
            'Vercel CLI needs it for auth. If this is gone, deploy fails (unauthorized).',
      );

      expect(
        workflow,
        contains('VERCEL_ORG_ID'),
        reason:
            'MISSING: deploy-web.yml must reference VERCEL_ORG_ID secret. '
            'Vercel CLI needs it to identify account. If this is gone, deploy fails.',
      );

      expect(
        workflow,
        contains('VERCEL_PROJECT_ID'),
        reason:
            'MISSING: deploy-web.yml must reference VERCEL_PROJECT_ID secret. '
            'Vercel CLI needs it to identify project. If this is gone, deploy fails.',
      );
    });

    test('must NEVER reference service_role key (security hole)', () {
      final String workflow = File('.github/workflows/deploy-web.yml')
          .readAsStringSync();

      // SUPABASE_ANON_KEY is public by design (RLS enforces security). Service role
      // key bypasses RLS (user A reads user B data). Must NEVER appear in workflow,
      // dart-define, or Flutter code.
      expect(
        workflow,
        isNot(contains('service_role')),
        reason:
            'SECURITY HOLE: deploy-web.yml must NEVER reference service_role key. '
            'That key bypasses RLS (all rows readable regardless of user_id). '
            'Only SUPABASE_ANON_KEY is allowed (public, confined by RLS). '
            'If service_role appears, it was leaked into workflow (critical bug).',
      );

      expect(
        workflow,
        isNot(contains('SERVICE_ROLE')),
        reason:
            'SECURITY HOLE: deploy-web.yml must NEVER reference SERVICE_ROLE (uppercase). '
            'Same as service_role: bypasses RLS. Only anon key allowed.',
      );
    });

    test('must NEVER reference Android signing material (wrong workflow)', () {
      final String workflow = File('.github/workflows/deploy-web.yml')
          .readAsStringSync();

      // Web workflow must NOT touch Android signing key (release.yml handles APK).
      // If keystore or KEYSTORE_PASSWORD appear, workflows were merged (wrong).
      expect(
        workflow,
        isNot(contains('keystore')),
        reason:
            'WRONG WORKFLOW: deploy-web.yml must NEVER reference keystore. '
            'Web deploy has no APK, no signing. Android signing lives in release.yml '
            'only (triggered by version tag). If keystore appears here, workflows '
            'were merged (wrong: signing key exposed to main-push trigger).',
      );

      expect(
        workflow,
        isNot(contains('KEYSTORE_PASSWORD')),
        reason:
            'WRONG WORKFLOW: deploy-web.yml must NEVER reference KEYSTORE_PASSWORD. '
            'That secret is for APK signing (release.yml only). If it appears here, '
            'workflows were merged and signing key exposed to web deploy.',
      );

      expect(
        workflow,
        isNot(contains('key.properties')),
        reason:
            'WRONG WORKFLOW: deploy-web.yml must NEVER reference key.properties. '
            'That file is for Android signing (release.yml only). If it appears here, '
            'workflows were merged.',
      );
    });
  });
}

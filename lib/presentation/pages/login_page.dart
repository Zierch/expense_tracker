// The web-only front door.
//
// Android never builds this page: there is no account on the phone and the app
// opens straight into its local database. On web every row belongs to a Supabase
// user, so the router sends visitors here until a session exists.

import 'package:expense_tracker/data/repositories/supabase_transaction_repository.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      // First login gets the same categories the Android app ships. Seeding is
      // best-effort: two tabs racing can hit the schema's unique constraint, and
      // that must not turn a successful sign-in into an error message. If it is
      // skipped, the first transaction creates the categories it needs anyway.
      try {
        await SupabaseTransactionRepository(Supabase.instance.client)
            .ensureSeed();
      } on Object catch (seedError) {
        debugPrint('Seed skipped after sign-in: $seedError');
      }
      if (!mounted) return;
      context.go('/');
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not sign in: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool signedIn = Supabase.instance.client.auth.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        actions: <Widget>[
          if (signedIn)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout_outlined),
              onPressed: _busy ? null : _signOut,
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Sign in', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Your records live in your own Supabase account. '
                    'Only you can read them.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: dark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const <String>[AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (String? value) => (value == null ||
                            !value.contains('@'))
                        ? 'Enter a valid email address'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const <String>[AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (String? value) => (value == null ||
                            value.length < 6)
                        ? 'Password must be at least 6 characters'
                        : null,
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? 'Signing in…' : 'Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

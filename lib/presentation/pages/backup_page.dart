import 'package:intl/intl.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:printing/printing.dart';

import 'package:expense_tracker/data/services/google_config.dart';
import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:expense_tracker/data/services/pdf_report_builder.dart';
import 'package:expense_tracker/domain/usecases/export_csv_usecase.dart';
import 'package:expense_tracker/domain/usecases/export_pdf_usecase.dart';
import 'package:expense_tracker/presentation/providers/backup_providers.dart';
import 'package:expense_tracker/presentation/providers/theme_provider.dart';
import 'package:expense_tracker/presentation/providers/update_providers.dart';

/// Semantic color, radius, and spacing tokens from DESIGN.md.
abstract final class _DesignTokens {
  static const Color primary = Color(0xFF0E5A44);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF111827);
  static const Color lightMuted = Color(0xFF6B7280);
  static const Color lightBorder = Color(0xFFE5E7EB);
  static const Color lightActivity = Color(0xFFE8F5E9);

  static const Color darkSurface = Color(0xFF1B2924);
  static const Color darkElevated = Color(0xFF263A30);
  static const Color darkTinted = Color(0xFF244239);
  static const Color darkText = Color(0xFFEDF7F1);
  static const Color darkMuted = Color(0xFFA8BDB3);
  static const Color darkBorder = Color(0xFF31443A);
  static const Color darkAccent = Color(0xFF83DFB7);

  static const double radiusPanel = 20.0;
  static const double radiusButton = 14.0;
  static const double radiusIcon = 12.0;

  static const double spacingScreen = 20.0;
  static const double spacingMedium = 16.0;
}

/// Standard 14px button style matching DESIGN.md `rounded.button: 14px`.
ButtonStyle _buttonStyle({
  BorderRadiusGeometry borderRadius =
      const BorderRadius.all(Radius.circular(_DesignTokens.radiusButton)),
}) {
  return ButtonStyle(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: borderRadius),
    ),
  );
}

/// 20px rounded settings panel matching DESIGN.md `rounded.panel: 20px`.
class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? _DesignTokens.darkSurface : _DesignTokens.lightSurface,
        borderRadius: BorderRadius.circular(_DesignTokens.radiusPanel),
        border: Border.all(
          color: isDark ? _DesignTokens.darkBorder : _DesignTokens.lightBorder,
        ),
      ),
      padding: padding,
      child: Material(color: Colors.transparent, child: child),
    );
  }
}

/// 12px rounded icon tile matching DESIGN.md `rounded.icon: 12px`.
class _SectionIconTile extends StatelessWidget {
  const _SectionIconTile({
    required this.icon,
    this.color,
    this.backgroundColor,
  });

  final IconData icon;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color effectiveBg = backgroundColor ??
        (isDark ? _DesignTokens.darkTinted : _DesignTokens.lightActivity);
    final Color effectiveColor = color ??
        (isDark ? _DesignTokens.darkAccent : _DesignTokens.primary);

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(_DesignTokens.radiusIcon),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: effectiveColor, size: 20),
    );
  }
}

/// Section header with icon tile, title, and optional badge/action.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Row(
      children: <Widget>[
        _SectionIconTile(icon: icon),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color:
                      isDark ? _DesignTokens.darkText : _DesignTokens.lightText,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? _DesignTokens.darkMuted
                        : _DesignTokens.lightMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Settings screen for appearance, Google Drive, and snapshot backup and sync.
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String? _error;

  /// Title shown above [_error]. Set by [_run], because a single error slot
  /// serves sign-in, sign-out and disconnect alike.
  String _errorTitle = 'Drive action failed';
  GoogleDriveService get _service => ref.read(googleDriveServiceProvider);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<GoogleSignInAccount?> account =
        ref.watch(googleAccountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: account.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: _DesignTokens.spacingScreen,
            vertical: _DesignTokens.spacingMedium,
          ),
          children: <Widget>[
            _buildNotice(
              icon: Icons.settings_suggest_outlined,
              title: 'Google Drive is not ready',
              message: _describeError(error),
              tone: Theme.of(context).colorScheme.error,
            ),
          ],
        ),
        data: (GoogleSignInAccount? user) =>
            user == null ? _buildSignedOut() : _buildSignedIn(user),
      ),
    );
  }

  Widget _buildAppearance() {
    final mode = ref.watch(themeModeProvider);
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    String label(ThemeMode value) => switch (value) {
          ThemeMode.system => 'Follow the system',
          ThemeMode.light => 'Light',
          ThemeMode.dark => 'Dark',
        };

    return _SettingsPanel(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionHeader(
            icon: Icons.palette_outlined,
            title: 'Appearance',
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Theme',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? _DesignTokens.darkText : _DesignTokens.lightText,
              ),
            ),
            subtitle: Text(
              label(mode),
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? _DesignTokens.darkMuted
                    : _DesignTokens.lightMuted,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: isDark ? _DesignTokens.darkMuted : _DesignTokens.lightMuted,
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(_DesignTokens.radiusPanel),
                ),
                backgroundColor: isDark
                    ? _DesignTokens.darkElevated
                    : _DesignTokens.lightSurface,
                title: const Text('Theme'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final choice in ThemeMode.values)
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        title: Text(label(choice)),
                        trailing: mode == choice
                            ? Icon(
                                Icons.check,
                                color: isDark
                                    ? _DesignTokens.darkAccent
                                    : _DesignTokens.primary,
                              )
                            : null,
                        onTap: () {
                          ref.read(themeModeProvider.notifier).set(choice);
                          Navigator.of(dialogContext).pop();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotSyncPreview() {
    final snapshotState = ref.watch(snapshotActionProvider);
    final signedIn = _service.currentAccount != null;
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return _SettingsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.sync_rounded,
            title: 'Backup & Sync',

          ),
          const SizedBox(height: 12),
          Text(
            'Back up all data across all months into a single complete snapshot '
            '(retaining up to 3 versions), or sync the latest complete snapshot.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? _DesignTokens.darkText : _DesignTokens.lightText,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? _DesignTokens.darkElevated.withOpacity(0.5)
                  : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? _DesignTokens.darkBorder
                    : _DesignTokens.lightBorder,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color:
                      isDark ? _DesignTokens.darkAccent : _DesignTokens.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    signedIn
                        ? 'Sync merges transactions without overwriting local data. Use one device at a time.'
                        : 'Sign in with Google to back up or sync.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? _DesignTokens.darkMuted
                          : _DesignTokens.lightMuted,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (signedIn) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: snapshotState.isLoading
                    ? null
                    : () => ref.read(snapshotActionProvider.notifier).run(backup: true),
                style: _buttonStyle(),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Back up all data'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: snapshotState.isLoading
                    ? null
                    : () => ref.read(snapshotActionProvider.notifier).run(backup: false),
                style: _buttonStyle(),
                icon: const Icon(Icons.sync_outlined),
                label: const Text('Sync latest backup'),
              ),
            ),
            if (snapshotState.isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (snapshotState.hasError) ...[
              const SizedBox(height: 12),
              Text('Backup action failed: ${snapshotState.error}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
            if (snapshotState.hasValue && snapshotState.value != null) ...[
              const SizedBox(height: 12),
              Text(snapshotState.value!, style: theme.textTheme.bodySmall),
            ],
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _handleSignIn,
                style: _buttonStyle(),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Connect Google Drive'),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Signed out
  // ---------------------------------------------------------------------------

  Widget _buildAccountSignedOut() {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return _SettingsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.cloud_outlined,
            title: 'Backup to Google Drive',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? _DesignTokens.darkElevated
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Not connected',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? _DesignTokens.darkMuted
                      : _DesignTokens.lightMuted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Sign in with your Google account to back up all data as a complete '
            'snapshot. Files are stored in the '
            '"${GoogleConfig.driveFolderName}" folder in your Drive.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? _DesignTokens.darkText : _DesignTokens.lightText,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _handleSignIn,
              style: _buttonStyle(),
              icon: _busy
                  ? const _ButtonSpinner()
                  : const Icon(Icons.login),
              label: const Text('Sign in with Google'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedOut() {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: _DesignTokens.spacingScreen,
        vertical: _DesignTokens.spacingMedium,
      ),
      children: <Widget>[
        _buildAppearance(),
        const SizedBox(height: _DesignTokens.spacingMedium),
        _buildAccountSignedOut(),
        const SizedBox(height: _DesignTokens.spacingMedium),
        _buildNotice(
          icon: Icons.lock_outline,
          title: 'Limited access',
          message:
              'This app only requests the drive.file scope, so it can only see '
              'the backup files it created itself — never the rest of your Drive.',
          tone: theme.colorScheme.primary,
        ),
        const SizedBox(height: _DesignTokens.spacingMedium),
        _buildSnapshotSyncPreview(),
        const SizedBox(height: _DesignTokens.spacingMedium),
        const _UpdateCard(),
        if (_error != null) ...<Widget>[
          const SizedBox(height: _DesignTokens.spacingMedium),
          _buildNotice(
            icon: Icons.error_outline,
            title: _errorTitle,
            message: _error!,
            tone: theme.colorScheme.error,
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Signed in
  // ---------------------------------------------------------------------------

  Widget _buildAccountSignedIn(GoogleSignInAccount user) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return _SettingsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.account_circle_outlined,
            title: 'Google Drive Account',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? _DesignTokens.darkTinted
                    : _DesignTokens.lightActivity,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Connected',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? _DesignTokens.darkAccent
                      : _DesignTokens.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              GoogleUserCircleAvatar(identity: user),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      user.displayName ?? 'Google account',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? _DesignTokens.darkText
                            : _DesignTokens.lightText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? _DesignTokens.darkMuted
                            : _DesignTokens.lightMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _handleSignOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignedIn(GoogleSignInAccount user) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: _DesignTokens.spacingScreen,
        vertical: _DesignTokens.spacingMedium,
      ),
      children: <Widget>[
        _buildAppearance(),
        const SizedBox(height: _DesignTokens.spacingMedium),
        _buildAccountSignedIn(user),
        const SizedBox(height: _DesignTokens.spacingMedium),
        _buildAccessNotice(),
        const SizedBox(height: _DesignTokens.spacingMedium),
        _buildSnapshotSyncPreview(),
        const SizedBox(height: _DesignTokens.spacingMedium),
        const _UpdateCard(),
        if (_error != null) ...<Widget>[
          const SizedBox(height: _DesignTokens.spacingMedium),
          _buildNotice(
            icon: Icons.error_outline,
            title: _errorTitle,
            message: _error!,
            tone: theme.colorScheme.error,
          ),
        ],
      ],
    );
  }

  /// Signing out keeps the Drive grant, so showing only a "Sign out" button
  /// would quietly imply that access has been withdrawn when it has not.
  Widget _buildAccessNotice() {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return _SettingsPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _SectionIconTile(
                icon: Icons.shield_outlined,
                color:
                    isDark ? _DesignTokens.darkAccent : _DesignTokens.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Access to your Drive',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? _DesignTokens.darkText
                        : _DesignTokens.lightText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The app keeps access to the "${GoogleConfig.driveFolderName}" '
            'folder until you disconnect, even after you sign out. '
            'Disconnecting revokes that access, so the next export asks for '
            'your permission again. Files already in Drive are not deleted.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? _DesignTokens.darkMuted
                  : _DesignTokens.lightMuted,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _handleDisconnect,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Disconnect'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared pieces
  // ---------------------------------------------------------------------------

  Widget _buildNotice({
    required IconData icon,
    required String title,
    required String message,
    required Color tone,
  }) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return _SettingsPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionIconTile(
            icon: icon,
            color: tone,
            backgroundColor: tone.withOpacity(0.12),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? _DesignTokens.darkText
                        : _DesignTokens.lightText,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? _DesignTokens.darkMuted
                        : _DesignTokens.lightMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _handleSignIn() async {
    await _run(
      () async {
        await _service.signIn();
      },
      errorTitle: 'Sign-in failed',
    );
  }

  Future<void> _handleSignOut() async {
    await _run(
      () async {
        await _service.signOut();
        if (mounted) ref.invalidate(snapshotActionProvider);
      },
      errorTitle: 'Sign out failed',
    );
  }

  Future<void> _handleDisconnect() async {
    final bool confirmed = await _confirmDisconnect();
    if (!confirmed || !mounted) return;

    await _run(
      () async {
        await _service.disconnect();
        if (mounted) ref.invalidate(snapshotActionProvider);
      },
      errorTitle: 'Disconnect failed',
    );
  }

  Future<bool> _confirmDisconnect() async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DesignTokens.radiusPanel),
        ),
        title: const Text('Disconnect Google Drive?'),
        content: const Text(
          'This app will lose access to the '
          '"${GoogleConfig.driveFolderName}" folder in your Drive. Backups you '
          'already uploaded stay there, and you can delete that folder from '
          'Drive yourself at any time. The next export will ask for your '
          'permission again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: _buttonStyle(),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _run(
    Future<void> Function() action, {
    String errorTitle = 'Export failed',
  }) async {
    setState(() {
      _busy = true;
      _error = null;
      _errorTitle = errorTitle;
    });

    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _describeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _describeError(Object error) {
    if (error is BackupException) return error.message;
    if (error is GoogleSignInException) {
      return error.description ?? error.code.name;
    }
    return error.toString();
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// A report of any date range, in either of two shapes: a PDF of totals,
/// categories and every transaction, drawn locally and handed to Android's share
/// sheet, or the same rows as a CSV file saved where the user chooses.
class ReportCard extends ConsumerStatefulWidget {
  const ReportCard({super.key});

  @override
  ConsumerState<ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<ReportCard> {
  static final DateFormat _day = DateFormat('d MMM yyyy');

  late DateTimeRange _range = _thisMonth();
  bool _busy = false;
  String? _error;
  String? _hint;

  static DateTimeRange _thisMonth() {
    final DateTime now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
  }

  String get _rangeLabel =>
      '${_day.format(_range.start)} – ${_day.format(_range.end)}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return _SettingsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionHeader(
            icon: Icons.summarize_outlined,
            title: 'Report',
          ),
          const SizedBox(height: 8),
          Text(
            'Any date range, as a PDF with totals and a breakdown per '
            'category, or as a CSV of the transactions for a spreadsheet. '
            'Both work offline and need no Google account.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? _DesignTokens.darkMuted : _DesignTokens.lightMuted,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickRange,
            style: _buttonStyle(),
            icon: const Icon(Icons.date_range_outlined, size: 18),
            label: Text(_rangeLabel),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _export,
              style: _buttonStyle(),
              icon: _busy
                  ? const _ButtonSpinner()
                  : const Icon(Icons.ios_share),
              label: Text(_busy ? 'Preparing…' : 'Export PDF'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _saveCsv,
              style: _buttonStyle(),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Save CSV'),
            ),
          ),
          if (_hint != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_hint!, style: theme.textTheme.bodySmall),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            SelectableText(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickRange() async {
    final DateTime today = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: _range,
      helpText: 'Report range',
    );

    if (picked == null || !mounted) return;
    setState(() {
      _range = picked;
      _error = null;
      _hint = null;
    });
  }

  Future<void> _saveCsv() async {
    setState(() {
      _busy = true;
      _error = null;
      _hint = null;
    });

    try {
      final CsvExport report = await ref
          .read(exportCsvUseCaseProvider)
          .call(from: _range.start, to: _range.end);

      if (report.transactionCount == 0) {
        if (mounted) {
          setState(() => _hint =
              'There are no transactions between $_rangeLabel, so there is '
                  'nothing to export yet.');
        }
        return;
      }

      final bool saved = await ref
          .read(filePickerServiceProvider)
          .saveTextFile(fileName: report.fileName, text: report.text);

      if (!mounted) return;
      if (!saved) return;
      setState(() => _hint = 'Saved ${report.fileName} with '
          '${report.transactionCount} '
          '${report.transactionCount == 1 ? 'transaction' : 'transactions'}.');
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save the CSV: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
      _hint = null;
    });

    try {
      final PdfReportData report = await ref
          .read(exportPdfUseCaseProvider)
          .call(from: _range.start, to: _range.end);

      if (report.transactionCount == 0) {
        if (mounted) {
          setState(() => _hint =
              'There are no transactions between $_rangeLabel, so there is '
                  'nothing to export yet.');
        }
        return;
      }

      final Uint8List bytes = await buildPdfReport(report);
      await Printing.sharePdf(bytes: bytes, filename: report.fileName);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not build the PDF: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

/// The "App updates" card: what runs now, what is newest, and one action per
/// state of the update flow.
class _UpdateCard extends ConsumerWidget {
  const _UpdateCard();

  static const String _firstRunNote =
      'Android may ask, once, to allow installs from this app before the '
      'installer opens.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppUpdateState state = ref.watch(appUpdateControllerProvider);

    return _SettingsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.system_update_outlined,
            title: 'App updates',
            trailing: IconButton(
              onPressed: state is UpdateChecking
                  ? null
                  : ref.read(appUpdateControllerProvider.notifier).checkNow,
              icon: const Icon(Icons.refresh),
              tooltip: 'Check for update',
            ),
          ),
          const SizedBox(height: 8),
          switch (state) {
            UpdateIdle() => const _UpdateText(
                'Not checked yet. The app checks when it opens; you can also '
                'run a check here at any time.',
              ),
            UpdateChecking() => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            UpdateUpToDate() => _UpdateText(
                'Up to date: version ${state.localVersion} is the newest '
                'published.',
              ),
            UpdateAvailable() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _UpdateText(
                    'Version ${state.release.version} (${(state.release.sizeInBytes / 1024 / 1024).toStringAsFixed(1)} MB) is available.',
                  ),
                  const SizedBox(height: 4),
                  const _UpdateText(
                    '$_firstRunNote The new version keeps your local data '
                    'and your Google Drive sign-in.',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: ref
                          .read(appUpdateControllerProvider.notifier)
                          .download,
                      style: _buttonStyle(),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download update'),
                    ),
                  ),
                ],
              ),
            UpdateDownloading() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: state.progress),
                  ),
                  const SizedBox(height: 4),
                  _UpdateText(
                    'Downloading… ${(state.progress * 100).round()}%',
                  ),
                ],
              ),
            UpdateReady() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _UpdateText(
                    'Downloaded and verified. $_firstRunNote',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: ref
                          .read(appUpdateControllerProvider.notifier)
                          .install,
                      style: _buttonStyle(),
                      icon: const Icon(Icons.install_mobile),
                      label: Text('Install version '
                          '${state.release.version}'),
                    ),
                  ),
                ],
              ),
            UpdateFailed() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _UpdateText(state.message, tone: theme.colorScheme.error),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: ref
                        .read(appUpdateControllerProvider.notifier)
                        .checkNow,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Try again'),
                  ),
                ],
              ),
          },
        ],
      ),
    );
  }
}

/// Plain body text inside the updates card.
class _UpdateText extends StatelessWidget {
  const _UpdateText(this.message, {this.tone});
  final String message;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Text(
      message,
      style: theme.textTheme.bodySmall?.copyWith(
        color: tone ?? theme.textTheme.bodySmall?.color,
      ),
    );
  }
}

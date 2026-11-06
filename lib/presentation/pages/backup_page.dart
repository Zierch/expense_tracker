import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'package:expense_tracker/data/services/google_config.dart';
import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:expense_tracker/data/services/pdf_report_builder.dart';
import 'package:expense_tracker/domain/usecases/export_csv_usecase.dart';
import 'package:expense_tracker/domain/usecases/export_month_usecase.dart';
import 'package:expense_tracker/domain/usecases/export_pdf_usecase.dart';
import 'package:expense_tracker/domain/usecases/import_month_usecase.dart';
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
  });

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color effectiveBg =
        isDark ? _DesignTokens.darkTinted : _DesignTokens.lightActivity;
    final Color effectiveColor =
        isDark ? _DesignTokens.darkAccent : _DesignTokens.primary;

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

/// Settings screen providing appearance options, Google Drive account
/// management, preview of full snapshot/sync, and monthly export/import controls.
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  static final DateFormat _monthLabel = DateFormat('MMMM yyyy');

  DateTime _month = DateTime.now();
  bool _busy = false;
  String? _error;

  /// Title shown above [_error]. Set by [_run], because a single error slot
  /// serves sign-in, export, sign-out and disconnect alike.
  String _errorTitle = 'Export failed';
  String? _hint;
  DriveUploadResult? _result;

  /// Which month of a batch export is being uploaded, for the button's label.
  String? _progress;

  /// How a finished batch export went. Kept apart from [_result], which answers
  /// for one month.
  String? _batch;

  GoogleDriveService get _service => ref.read(googleDriveServiceProvider);

  bool get _isCurrentMonth {
    final DateTime now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

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

  /// Preview of the full snapshot & sync design. Both actions are intentionally
  /// disabled and explicitly marked unavailable to protect live user data from
  /// accidental overwrites.
  Widget _buildSnapshotSyncPreview() {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return _SettingsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.sync_rounded,
            title: 'Backup & Sync',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? _DesignTokens.darkElevated
                    : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Unavailable',
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
                    'Full snapshot backup and sync are currently unavailable. '
                    'Existing multi-month data is safely preserved using the '
                    'monthly operations below to prevent accidental data overwrite.',
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
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message:
                  'Full snapshot backup is currently unavailable; use monthly export below.',
              child: FilledButton.icon(
                onPressed: null,
                style: _buttonStyle(),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Back up all data'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message:
                  'Full snapshot sync is currently unavailable; use monthly restore below.',
              child: OutlinedButton.icon(
                onPressed: null,
                style: _buttonStyle(),
                icon: const Icon(Icons.sync_outlined),
                label: const Text('Sync latest backup'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Moves the selector by [delta] months.
  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _result = null;
      _error = null;
      _hint = null;
    });
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
            'Sign in with your Google account to archive every month as a '
            'JSON file. Files are stored in the '
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
        const _ImportCard(signedIn: false),
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

  Widget _buildMonthlyExportCard() {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final String label = _monthLabel.format(_month);

    return _SettingsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionHeader(
            icon: Icons.cloud_upload_outlined,
            title: 'Monthly Drive Backup',
            subtitle: 'Export individual monthly JSON backups',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? _DesignTokens.darkElevated
                  : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? _DesignTokens.darkBorder
                    : _DesignTokens.lightBorder,
              ),
            ),
            child: Row(
              children: <Widget>[
                IconButton(
                  onPressed: _busy ? null : () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous month',
                ),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? _DesignTokens.darkText
                          : _DesignTokens.lightText,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _busy || _isCurrentMonth
                      ? null
                      : () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next month',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Exports every transaction of $label into '
            '"${GoogleConfig.driveFolderName}" as a JSON file.',
            textAlign: TextAlign.start,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? _DesignTokens.darkMuted
                  : _DesignTokens.lightMuted,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _handleExport,
              style: _buttonStyle(),
              icon: _busy
                  ? const _ButtonSpinner()
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(
                _busy ? 'Uploading…' : 'Export $label to Drive',
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _handleExportAll,
              style: _buttonStyle(),
              icon: const Icon(Icons.library_add_check_outlined),
              label: Text(_progress ?? 'Export every month to Drive'),
            ),
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
        _buildMonthlyExportCard(),
        const SizedBox(height: _DesignTokens.spacingMedium),
        const _ImportCard(signedIn: true),
        const SizedBox(height: _DesignTokens.spacingMedium),
        const _UpdateCard(),
        if (_result != null) ...<Widget>[
          const SizedBox(height: _DesignTokens.spacingMedium),
          _buildResult(_result!),
        ],
        if (_batch != null) ...<Widget>[
          const SizedBox(height: _DesignTokens.spacingMedium),
          _buildNotice(
            icon: Icons.check_circle_outline,
            title: 'Backup complete',
            message: _batch!,
            tone: theme.colorScheme.primary,
          ),
        ],
        if (_hint != null) ...<Widget>[
          const SizedBox(height: _DesignTokens.spacingMedium),
          _buildNotice(
            icon: Icons.info_outline,
            title: 'Nothing to back up',
            message: _hint!,
            tone: theme.colorScheme.onSurfaceVariant,
          ),
        ],
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

  Widget _buildResult(DriveUploadResult result) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color accent =
        isDark ? _DesignTokens.darkAccent : _DesignTokens.primary;

    return _SettingsPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionIconTile(
            icon: Icons.check_circle_outline,
            color: accent,
            backgroundColor: accent.withOpacity(0.12),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  result.replacedExisting
                      ? 'Backup updated in Google Drive'
                      : 'Backup uploaded to Google Drive',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? _DesignTokens.darkText
                        : _DesignTokens.lightText,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  result.fileName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? _DesignTokens.darkText
                        : _DesignTokens.lightText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Folder: ${result.folderName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? _DesignTokens.darkMuted
                        : _DesignTokens.lightMuted,
                  ),
                ),
                if (result.webViewLink != null) ...<Widget>[
                  const SizedBox(height: 8),
                  SelectableText(
                    result.webViewLink!,
                    style: theme.textTheme.bodySmall?.copyWith(color: accent),
                  ),
                ],
              ],
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
        if (mounted) {
          setState(() => _result = null);
        }
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
        if (mounted) {
          setState(() => _result = null);
        }
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

  Future<void> _handleExport() async {
    await _run(() async {
      final MonthExport export =
          await ref.read(exportMonthUseCaseProvider).call(_month);

      if (export.transactionCount == 0) {
        if (mounted) {
          setState(() {
            _hint =
                'There are no transactions in ${export.monthLabel}, so there '
                'is nothing to back up yet.';
          });
        }
        return;
      }

      final DriveUploadResult result = await _service.uploadJson(
        fileName: export.fileName,
        data: export.json,
      );

      if (mounted) {
        setState(() => _result = result);
      }
    });
  }

  Future<void> _handleExportAll() async {
    setState(() {
      _busy = true;
      _error = null;
      _errorTitle = 'Backup failed';
      _hint = null;
      _result = null;
      _batch = null;
      _progress = null;
    });

    int uploaded = 0;
    int months = 0;
    try {
      final ExportMonthUseCase export = ref.read(exportMonthUseCaseProvider);
      final List<DateTime> all = await export.monthsWithTransactions();
      months = all.length;

      if (months == 0) {
        if (mounted) {
          setState(() => _hint = 'There are no transactions in any month yet, '
              'so there is nothing to back up.');
        }
        return;
      }

      for (final DateTime month in all) {
        if (!mounted) return;
        setState(() => _progress = 'Exporting ${uploaded + 1} of $months...');

        final MonthExport monthExport = await export.call(month);
        await _service.uploadJson(
          fileName: monthExport.fileName,
          data: monthExport.json,
        );
        uploaded++;
      }

      if (mounted) {
        setState(() => _batch = 'Uploaded $uploaded '
            '${uploaded == 1 ? 'month' : 'months'} to '
            '"${GoogleConfig.driveFolderName}", one file per month.');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = uploaded == 0
            ? _describeError(error)
            : '${_describeError(error)}\n'
                '$uploaded of $months months were uploaded before it stopped.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    String errorTitle = 'Export failed',
  }) async {
    setState(() {
      _busy = true;
      _error = null;
      _errorTitle = errorTitle;
      _hint = null;
      _result = null;
      _batch = null;
      _progress = null;
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

/// Restores transactions from a backup: a file the user picks, or the files
/// already archived in Drive.
class _ImportCard extends ConsumerStatefulWidget {
  const _ImportCard({required this.signedIn});

  final bool signedIn;

  @override
  ConsumerState<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends ConsumerState<_ImportCard> {
  bool _busy = false;

  /// What the last import did, and what went wrong if anything did.
  String? _summary;
  String? _error;

  Future<void> _importFile() async {
    setState(() {
      _busy = true;
      _summary = null;
      _error = null;
    });

    try {
      final String? text =
          await ref.read(filePickerServiceProvider).pickJsonText();
      // Backing out of the chooser is not a failure: there is nothing to report.
      if (text == null || !mounted) return;

      final ImportResult result =
          await ref.read(importMonthUseCaseProvider).call(text);
      if (!mounted) return;
      setState(() => _summary = _describeImport(result));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeImportError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromDrive() async {
    setState(() {
      _busy = true;
      _summary = null;
      _error = null;
    });

    final List<DriveBackupFile> files;
    try {
      files = await ref.read(googleDriveServiceProvider).listBackupFiles();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeImportError(error));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    if (files.isEmpty) {
      setState(() => _summary =
          'No backups found in the "${GoogleConfig.driveFolderName}" folder in your Drive.');
      return;
    }

    final String? outcome = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_DesignTokens.radiusPanel),
        ),
      ),
      builder: (BuildContext context) => _DriveRestoreSheet(files: files),
    );

    if (!mounted || outcome == null) return;
    setState(() => _summary = outcome);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return _SettingsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionHeader(
            icon: Icons.settings_backup_restore,
            title: 'Import a backup',
          ),
          const SizedBox(height: 12),
          Text(
            'Restores transactions from a JSON backup this app exported. Rows '
            'that are already stored are left as they are, so importing the '
            'same file twice changes nothing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? _DesignTokens.darkText : _DesignTokens.lightText,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : _importFile,
              style: _buttonStyle(),
              icon: _busy
                  ? const _ButtonSpinner()
                  : const Icon(Icons.folder_open),
              label: const Text('Choose a backup file'),
            ),
          ),
          if (widget.signedIn) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restoreFromDrive,
                style: _buttonStyle(),
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('Restore from Google Drive'),
              ),
            ),
          ],
          if (_summary != null) ...<Widget>[
            const SizedBox(height: 12),
            _UpdateText(
              _summary!,
              tone: isDark ? _DesignTokens.darkAccent : _DesignTokens.primary,
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            _UpdateText(_error!, tone: theme.colorScheme.error),
          ],
        ],
      ),
    );
  }
}

/// The months found in Drive, with a checkbox each, and the import itself.
class _DriveRestoreSheet extends ConsumerStatefulWidget {
  const _DriveRestoreSheet({required this.files});

  final List<DriveBackupFile> files;

  @override
  ConsumerState<_DriveRestoreSheet> createState() => _DriveRestoreSheetState();
}

class _DriveRestoreSheetState extends ConsumerState<_DriveRestoreSheet> {
  static final RegExp _nameStamp = RegExp(r'expense-tracker-(\d{4})-(\d{2})');
  static final DateFormat _monthLabel = DateFormat('MMMM yyyy');

  late final Set<String> _selected =
      widget.files.map((DriveBackupFile file) => file.id).toSet();

  bool _busy = false;
  int _done = 0;
  String? _failure;

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _failure = null;
      _done = 0;
    });

    int months = 0;
    int imported = 0;
    int duplicates = 0;
    int unreadable = 0;
    int failed = 0;

    final List<DriveBackupFile> chosen = widget.files
        .where((DriveBackupFile file) => _selected.contains(file.id))
        .toList();

    for (final DriveBackupFile file in chosen) {
      try {
        final String json =
            await ref.read(googleDriveServiceProvider).downloadJson(file.id);
        final ImportResult result =
            await ref.read(importMonthUseCaseProvider).call(json);
        months++;
        imported += result.imported;
        duplicates += result.duplicates;
        unreadable += result.unreadable;
      } catch (error) {
        failed++;
        _failure ??= _describeImportError(error);
      }
      if (!mounted) return;
      setState(() => _done++);
    }

    if (!mounted) return;

    if (months == 0 && _failure != null) {
      Navigator.pop(context, _failure);
      return;
    }

    Navigator.pop(
      context,
      _describeDriveRestore(
        months: months,
        imported: imported,
        duplicates: duplicates,
        unreadable: unreadable,
        failed: failed,
      ),
    );
  }

  String _labelFor(DriveBackupFile file) {
    final Match? match = _nameStamp.firstMatch(file.name);
    if (match == null) return file.name;

    final int? year = int.tryParse(match.group(1)!);
    final int? month = int.tryParse(match.group(2)!);
    if (year == null || month == null || month < 1 || month > 12) {
      return file.name;
    }

    return _monthLabel.format(DateTime(year, month));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool allSelected = _selected.length == widget.files.length;

    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Backups in Google Drive',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose the months to restore. Transactions already stored are '
                'skipped.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: allSelected,
                onChanged: _busy
                    ? null
                    : (bool? value) => setState(() {
                          _selected.clear();
                          if (value ?? false) {
                            _selected.addAll(
                              widget.files
                                  .map((DriveBackupFile file) => file.id),
                            );
                          }
                        }),
                title: const Text('All months'),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: widget.files
                      .map((DriveBackupFile file) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _selected.contains(file.id),
                            onChanged: _busy
                                ? null
                                : (bool? value) => setState(() {
                                      if (value ?? false) {
                                        _selected.add(file.id);
                                      } else {
                                        _selected.remove(file.id);
                                      }
                                    }),
                            title: Text(_labelFor(file)),
                            subtitle: Text(
                              file.modifiedTime == null
                                  ? file.name
                                  : '${file.name} · '
                                      '${DateFormat('d MMM yyyy').format(file.modifiedTime!)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ))
                      .toList(),
                ),
              ),
              if (_failure != null && !_busy) ...<Widget>[
                const SizedBox(height: 8),
                _UpdateText(_failure!, tone: theme.colorScheme.error),
              ],
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy || _selected.isEmpty ? null : _import,
                      style: _buttonStyle(),
                      icon: _busy
                          ? const _ButtonSpinner()
                          : const Icon(Icons.download),
                      label: Text(
                        _busy
                            ? 'Importing $_done of ${_selected.length}...'
                            : 'Import ${_selected.length} selected',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One file's outcome, in words.
String _describeImport(ImportResult result) {
  final String month =
      result.monthLabel.isEmpty ? 'the backup' : result.monthLabel;
  final StringBuffer summary = StringBuffer(
    'Imported ${result.imported} ${result.imported == 1 ? 'transaction' : 'transactions'} '
    'from $month',
  );
  if (result.duplicates > 0) {
    summary.write(', ${result.duplicates} already there');
  }
  if (result.unreadable > 0) {
    summary.write(', ${_unreadableClause(result.unreadable)}');
  }
  summary.write('.');
  return summary.toString();
}

String _unreadableClause(int unreadable) => unreadable == 1
    ? 'one row could not be read'
    : '$unreadable rows could not be read';

/// Several files' outcome, in words.
String _describeDriveRestore({
  required int months,
  required int imported,
  required int duplicates,
  required int unreadable,
  required int failed,
}) {
  final StringBuffer summary = StringBuffer(
    'Imported $imported ${imported == 1 ? 'transaction' : 'transactions'} '
    'from $months ${months == 1 ? 'month' : 'months'}',
  );
  if (duplicates > 0) {
    summary.write(', $duplicates already there');
  }
  if (unreadable > 0) {
    summary.write(', ${_unreadableClause(unreadable)}');
  }
  if (failed > 0) {
    summary.write(
      '. $failed ${failed == 1 ? 'file' : 'files'} could not be read',
    );
    summary.write('.');
    return summary.toString();
  }
  summary.write('.');
  return summary.toString();
}

/// A failure's message, when the failure was raised for the user to read.
String _describeImportError(Object error) {
  if (error is ImportException) return error.message;
  if (error is BackupException) return error.message;
  return '$error';
}

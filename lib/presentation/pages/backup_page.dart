import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import 'package:expense_tracker/data/services/google_config.dart';
import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:expense_tracker/domain/usecases/export_month_usecase.dart';
import 'package:expense_tracker/presentation/providers/backup_providers.dart';

/// Signs in with Google and archives a month's transactions to Google Drive.
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

  /// Title shown above [_error]. It is set by [_run], because a single error
  /// slot serves sign-in, export, sign-out and disconnect alike, and reporting
  /// a failed disconnect under the heading "Export failed" would be wrong.
  String _errorTitle = 'Export failed';
  String? _hint;
  DriveUploadResult? _result;

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
      appBar: AppBar(title: const Text('Backup')),
      body: account.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => ListView(
          padding: const EdgeInsets.all(16),
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

  /// Moves the selector by [delta] months.
  ///
  /// Relies on `DateTime`'s normalisation of out-of-range months — stepping
  /// back from January yields `DateTime(year, 0, 1)`, which is December of the
  /// previous year. `test/month_navigation_test.dart` locks that behaviour in.
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

  Widget _buildSignedOut() {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.cloud_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Backup to Google Drive',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Sign in with your Google account to archive every month as a '
                  'JSON file. Files are stored in the '
                  '"${GoogleConfig.driveFolderName}" folder in your Drive.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _handleSignIn,
                    icon: _busy
                        ? const _ButtonSpinner()
                        : const Icon(Icons.login),
                    label: const Text('Sign in with Google'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildNotice(
          icon: Icons.lock_outline,
          title: 'Limited access',
          message:
              'This app only requests the drive.file scope, so it can only see '
              'the backup files it created itself — never the rest of your Drive.',
          tone: theme.colorScheme.primary,
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
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

  Widget _buildSignedIn(GoogleSignInAccount user) {
    final ThemeData theme = Theme.of(context);
    final String label = _monthLabel.format(_month);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                GoogleUserCircleAvatar(identity: user),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        user.displayName ?? 'Google account',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        user.email,
                        style: theme.textTheme.bodySmall,
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
          ),
        ),
        const SizedBox(height: 12),
        _buildAccessNotice(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
            child: Column(
              children: <Widget>[
                Row(
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
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Exports every transaction of $label into '
                    '"${GoogleConfig.driveFolderName}" as a JSON file.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _handleExport,
                      icon: _busy
                          ? const _ButtonSpinner()
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        _busy ? 'Uploading…' : 'Export $label to Drive',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_result != null) ...<Widget>[
          const SizedBox(height: 12),
          _buildResult(_result!),
        ],
        if (_hint != null) ...<Widget>[
          const SizedBox(height: 12),
          _buildNotice(
            icon: Icons.info_outline,
            title: 'Nothing to back up',
            message: _hint!,
            tone: theme.colorScheme.onSurfaceVariant,
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
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
  /// would quietly imply that access has been withdrawn when it has not. A user
  /// who handed over a Google permission deserves both the difference in plain
  /// words and the action that actually revokes it.
  Widget _buildAccessNotice() {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Access to your Drive',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The app keeps access to the "${GoogleConfig.driveFolderName}" '
              'folder until you disconnect, even after you sign out. '
              'Disconnecting revokes that access, so the next export asks for '
              'your permission again. Files already in Drive are not deleted.',
              style: theme.textTheme.bodySmall,
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
      ),
    );
  }

  Widget _buildResult(DriveUploadResult result) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.check_circle_outline, color: accent),
            const SizedBox(width: 12),
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
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    result.fileName,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Folder: ${result.folderName}',
                    style: theme.textTheme.bodySmall,
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Selectable, because a failure banner can carry the
                  // myaccount.google.com address for withdrawing access by hand,
                  // and a link the user cannot copy is not much of a fallback.
                  SelectableText(message, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
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

  /// Revoking access means the next export shows Google's consent screen again,
  /// which is worth one confirmation step before it happens.
  Future<bool> _confirmDisconnect() async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
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

  /// Runs [action] with the busy flag and error banner wired up.
  ///
  /// [errorTitle] names the operation in the failure banner, so a user reading
  /// it can tell which action actually failed.
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

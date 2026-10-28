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
import 'package:expense_tracker/presentation/providers/update_providers.dart';

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

  /// Which month of a batch export is being uploaded, for the button's label.
  String? _progress;

  /// How a finished batch export went. Kept apart from [_result], which answers
  /// for one month: a count of months is not a [DriveUploadResult].
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
                    Icon(Icons.cloud_outlined,
                        color: theme.colorScheme.primary),
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
        const SizedBox(height: 12),
        const _ImportCard(signedIn: false),
        const SizedBox(height: 12),
        const _ReportCard(),
        const SizedBox(height: 12),
        const _UpdateCard(),
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
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _handleExportAll,
                      icon: const Icon(Icons.library_add_check_outlined),
                      label: Text(_progress ?? 'Export every month to Drive'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _ImportCard(signedIn: true),
        const SizedBox(height: 12),
        const _ReportCard(),
        const SizedBox(height: 12),
        const _UpdateCard(),
        if (_result != null) ...<Widget>[
          const SizedBox(height: 12),
          _buildResult(_result!),
        ],
        if (_batch != null) ...<Widget>[
          const SizedBox(height: 12),
          _buildNotice(
            icon: Icons.check_circle_outline,
            title: 'Backup complete',
            message: _batch!,
            tone: theme.colorScheme.primary,
          ),
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

  /// Uploads every month that holds a transaction, one file per month.
  ///
  /// One month at a time rather than all at once: the button says which month it
  /// is on, and a failure names how far it got. Each month is its own file with
  /// its own name, so running this again replaces the months it already wrote
  /// instead of duplicating them — a retry after a failure costs only time.
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
///
/// No sign-in either way. The PDF needs no storage permission because it leaves
/// through whichever app the user picks; the CSV goes through Android's own
/// "Save as" dialog, which needs no permission for the same reason.
class _ReportCard extends ConsumerStatefulWidget {
  const _ReportCard();

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  static final DateFormat _day = DateFormat('d MMM yyyy');

  late DateTimeRange _range = _thisMonth();
  bool _busy = false;
  String? _error;
  String? _hint;

  /// Opens on the month so far: the range most people want to hand over.
  static DateTimeRange _thisMonth() {
    final DateTime now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
  }

  String get _rangeLabel =>
      '${_day.format(_range.start)} – ${_day.format(_range.end)}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.summarize_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Report',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Any date range, as a PDF with totals and a breakdown per '
              'category, or as a CSV of the transactions for a spreadsheet. '
              'Both work offline and need no Google account.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickRange,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(_rangeLabel),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _export,
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

  /// The same range as the CSV, saved through Android's "Save as" dialog.
  ///
  /// Separate from [_export] rather than a format switch: the two files leave the
  /// app in different ways (share sheet, storage), and a failure has to name the
  /// one that failed.
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
      // Backing out of the dialog is not a failure, and there is nothing to
      // report: a "cancelled" notice would only be noise.
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
///
/// The app ships outside the Play Store, so updates arrive as an APK: check →
/// download → hand the file to Android's installer. Every state has exactly one
/// obvious action, and errors name what failed and offer the retry.
class _UpdateCard extends ConsumerWidget {
  const _UpdateCard();

  static const String _firstRunNote =
      'Android may ask, once, to allow installs from this app before the '
      'installer opens.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppUpdateState state = ref.watch(appUpdateControllerProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.system_update_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'App updates',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: state is UpdateChecking
                      ? null
                      : ref.read(appUpdateControllerProvider.notifier).checkNow,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Check for update',
                ),
              ],
            ),
            switch (state) {
              // Never checked: say so, and mention when it does happen on its
              // own so a user can connect the banner up top to this page.
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
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download update'),
                      ),
                    ),
                  ],
                ),
              UpdateDownloading() => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    LinearProgressIndicator(value: state.progress),
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
                    const SizedBox(height: 4),
                    const _UpdateText(
                      'Nothing was changed — you can retry the check.',
                    ),
                  ],
                ),
            },
          ],
        ),
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
///
/// It sits next to the export cards because it is the inverse of what they do,
/// and the file half works signed out — a backup on the phone has nothing to do
/// with a Google account.
class _ImportCard extends ConsumerStatefulWidget {
  const _ImportCard({required this.signedIn});

  /// Whether the Drive half is offered. The file half is always there.
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

    // Not dismissible by drag or by tapping outside: a restore of several
    // months takes a while, and a sheet that vanished mid-way would dispose the
    // loop that is writing rows — leaving some months in and the user told
    // nothing about which. The sheet owns its own Close button instead.
    final String? outcome = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (BuildContext context) => _DriveRestoreSheet(files: files),
    );

    if (!mounted || outcome == null) return;
    setState(() => _summary = outcome);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.settings_backup_restore,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Import a backup',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Restores transactions from a JSON backup this app exported. Rows '
              'that are already stored are left as they are, so importing the '
              'same file twice changes nothing.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _importFile,
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
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Restore from Google Drive'),
                ),
              ),
            ],
            if (_summary != null) ...<Widget>[
              const SizedBox(height: 12),
              _UpdateText(_summary!, tone: theme.colorScheme.primary),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _UpdateText(_error!, tone: theme.colorScheme.error),
            ],
          ],
        ),
      ),
    );
  }
}

/// The months found in Drive, with a checkbox each, and the import itself.
///
/// The work happens here rather than behind the sheet so that progress has
/// somewhere to be shown: a restore of eight months is eight downloads, and a
/// button that only spins cannot say whether it is on the second or the last.
class _DriveRestoreSheet extends ConsumerStatefulWidget {
  const _DriveRestoreSheet({required this.files});

  final List<DriveBackupFile> files;

  @override
  ConsumerState<_DriveRestoreSheet> createState() => _DriveRestoreSheetState();
}

class _DriveRestoreSheetState extends ConsumerState<_DriveRestoreSheet> {
  static final RegExp _nameStamp = RegExp(r'expense-tracker-(\d{4})-(\d{2})');
  static final DateFormat _monthLabel = DateFormat('MMMM yyyy');

  /// Everything is chosen to begin with: a restore is usually "put it all back".
  late final Set<String> _selected =
      widget.files.map((DriveBackupFile file) => file.id).toSet();

  bool _busy = false;
  int _done = 0;

  /// The first failure's own words, when there was one. A count of failures says
  /// something went wrong; the message says what.
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
        // One unreadable file must not abandon the rest: the others are still
        // the user's data, and the summary says how many did not come through.
        failed++;
        _failure ??= _describeImportError(error);
      }
      if (!mounted) return;
      setState(() => _done++);
    }

    if (!mounted) return;

    // Nothing landed at all: the file's own message is the useful thing to say,
    // not a tally of zeroes.
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
    if (year == null || month == null || month < 1 || month > 12)
      return file.name;

    return _monthLabel.format(DateTime(year, month));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool allSelected = _selected.length == widget.files.length;

    return PopScope(
      // The Android back gesture goes the same way as the Close button: it is
      // refused while rows are being written, and allowed once they are not.
      canPop: !_busy,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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

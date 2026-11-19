// Web Settings: the same work the Android Settings page does, with the storage
// backend swapped. No Google Drive, no APK updater, no share sheet — those are
// Android services and have no meaning for a page served by Vercel.

import 'dart:convert';
import 'dart:typed_data';

import 'package:expense_tracker/data/services/browser_download.dart';
import 'package:expense_tracker/data/services/browser_file_picker.dart';
import 'package:expense_tracker/data/services/pdf_report_builder.dart';
import 'package:expense_tracker/domain/entities/month_range.dart';
import 'package:expense_tracker/domain/usecases/export_csv_usecase.dart';
import 'package:expense_tracker/domain/usecases/export_pdf_usecase.dart';
import 'package:expense_tracker/domain/usecases/export_snapshot_usecase.dart';
import 'package:expense_tracker/domain/usecases/import_snapshot_usecase.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WebSettingsPage extends ConsumerStatefulWidget {
  const WebSettingsPage({super.key});

  @override
  ConsumerState<WebSettingsPage> createState() => _WebSettingsPageState();
}

class _WebSettingsPageState extends ConsumerState<WebSettingsPage> {
  bool _busy = false;
  String? _message;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not finish: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportJson() => _run(() async {
        final SnapshotExport export =
            await ExportSnapshotUseCase(ref.read(transactionRepositoryProvider))();
        downloadBytes(
          'expense-tracker-snapshot.json',
          Uint8List.fromList(utf8.encode(export.jsonText)),
          mime: 'application/json',
        );
        setState(() => _message = 'Snapshot downloaded.');
      });

  Future<void> _importJson() => _run(() async {
        final ({String name, Uint8List bytes})? picked = await pickTextFile();
        if (picked == null) return;
        final SnapshotImportResult result =
            await ImportSnapshotUseCase(ref.read(transactionRepositoryProvider))(
          utf8.decode(picked.bytes),
        );
        setState(() => _message =
            'Imported ${result.imported} rows, ${result.duplicates} already stored.');
      });

  Future<void> _exportCsv() => _run(() async {
        final MonthRange month = MonthRange.of(DateTime.now());
        final CsvExport csv = await ExportCsvUseCase(
          ref.read(transactionRepositoryProvider),
        )(from: month.start, to: month.end);
        downloadBytes(
          csv.fileName,
          Uint8List.fromList(utf8.encode(csv.text)),
          mime: 'text/csv',
        );
        setState(() => _message = 'CSV downloaded.');
      });

  Future<void> _exportPdf() => _run(() async {
        final MonthRange month = MonthRange.of(DateTime.now());
        final PdfReportData data = await ExportPdfUseCase(
          ref.read(transactionRepositoryProvider),
        )(from: month.start, to: month.end);
        final Uint8List bytes = await buildPdfReport(data);
        downloadBytes(
          data.fileName,
          bytes,
          mime: 'application/pdf',
        );
        setState(() => _message = 'PDF downloaded.');
      });

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ThemeMode mode = ref.watch(themeModeProvider);
    final String email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('Appearance', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<ThemeMode>(
            initialValue: mode,
            decoration: const InputDecoration(
              labelText: 'Theme',
              border: OutlineInputBorder(),
            ),
            items: const <DropdownMenuItem<ThemeMode>>[
              DropdownMenuItem(value: ThemeMode.system, child: Text('Follow the system')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
            onChanged: (ThemeMode? value) {
              if (value != null) {
                ref.read(themeModeProvider.notifier).set(value);
              }
            },
          ),
          const SizedBox(height: 28),
          Text('Cloud data', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('Signed in as $email', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            'Your records are stored in Supabase and are visible only to this '
            'account. The Android app keeps its own offline copy; the two do '
            'not sync.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 28),
          Text('Backup & export', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _exportJson,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Export all data as JSON'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importJson,
            icon: const Icon(Icons.upload_outlined),
            label: const Text('Import a JSON backup'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _exportCsv,
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Export this month as CSV'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export this month as PDF'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_message!, style: theme.textTheme.bodySmall),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout_outlined),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

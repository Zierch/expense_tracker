import 'dart:convert';

import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:expense_tracker/data/services/snapshot_drive_service.dart';
import 'package:expense_tracker/domain/usecases/export_snapshot_usecase.dart';
import 'package:expense_tracker/domain/usecases/import_snapshot_usecase.dart';

/// Coordinates explicit backup and sync operations for one active device.
class SnapshotCoordinator {
  SnapshotCoordinator(this.drive, this.exporter, this.importer);

  final SnapshotDriveService drive;
  final ExportSnapshotUseCase exporter;
  final ImportSnapshotUseCase importer;
  static bool _busy = false;

  Future<String> backup() async {
    if (_busy) throw BackupException('A backup or sync is already running.');
    _busy = true;
    try {
      final snapshot = await exporter();
      return await drive.uploadSnapshot(utf8.encode(snapshot.jsonText));
    } finally {
      _busy = false;
    }
  }

  Future<SnapshotImportResult> sync() async {
    if (_busy) throw BackupException('A backup or sync is already running.');
    _busy = true;
    try {
      final snapshots = await drive.listOwnedSnapshots();
      if (snapshots.isEmpty) {
        throw BackupException('No snapshot found. Back up all data first.');
      }
      final id = snapshots.first['id'];
      if (id is! String || id.isEmpty) throw BackupException('Snapshot metadata is invalid.');
      final text = utf8.decode(await drive.downloadFile(id));
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic> ||
          decoded['app'] != 'Expense Tracker' ||
          decoded['backupType'] != 'snapshot' ||
          decoded['schemaVersion'] != 2) {
        throw BackupException('Latest snapshot is invalid or unsupported. No data was imported.');
      }
      return await importer(text, strict: true);
    } finally {
      _busy = false;
    }
  }
}

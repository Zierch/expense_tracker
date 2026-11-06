import 'dart:convert';

import 'package:expense_tracker/data/services/snapshot_drive_service.dart';
import 'package:expense_tracker/domain/entities/import_transaction.dart';
import 'package:expense_tracker/domain/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/usecases/export_snapshot_usecase.dart';
import 'package:expense_tracker/domain/usecases/import_month_usecase.dart';

/// Failure during legacy backup migration or validation.
class MigrationException extends ImportException {
  MigrationException(super.message);
}

/// Status of the migration attempt.
enum MigrationStatus {
  completed,
  skippedSnapshotsExist,
  noLegacyFiles,
}

/// Outcome of a legacy backup migration.
class MigrationResult {
  const MigrationResult({
    required this.status,
    required this.filesProcessed,
    required this.importedCount,
    required this.duplicatesCount,
    required this.totalTransactions,
    this.preparedSnapshot,
    this.skipReason,
  });

  factory MigrationResult.completed({
    required int filesProcessed,
    required int importedCount,
    required int duplicatesCount,
    required int totalTransactions,
    required SnapshotExport preparedSnapshot,
  }) {
    return MigrationResult(
      status: MigrationStatus.completed,
      filesProcessed: filesProcessed,
      importedCount: importedCount,
      duplicatesCount: duplicatesCount,
      totalTransactions: totalTransactions,
      preparedSnapshot: preparedSnapshot,
    );
  }

  factory MigrationResult.skipped({required String reason}) {
    return MigrationResult(
      status: MigrationStatus.skippedSnapshotsExist,
      filesProcessed: 0,
      importedCount: 0,
      duplicatesCount: 0,
      totalTransactions: 0,
      skipReason: reason,
    );
  }

  factory MigrationResult.noLegacyFiles() {
    return const MigrationResult(
      status: MigrationStatus.noLegacyFiles,
      filesProcessed: 0,
      importedCount: 0,
      duplicatesCount: 0,
      totalTransactions: 0,
    );
  }

  final MigrationStatus status;
  final int filesProcessed;
  final int importedCount;
  final int duplicatesCount;
  final int totalTransactions;
  final SnapshotExport? preparedSnapshot;
  final String? skipReason;

  bool get isCompleted => status == MigrationStatus.completed;
  bool get isSkipped => status == MigrationStatus.skippedSnapshotsExist;
  bool get hasNoFiles => status == MigrationStatus.noLegacyFiles;
}

/// One legacy monthly backup file payload.
class LegacyFileEntry {
  const LegacyFileEntry({
    required this.name,
    required this.content,
    this.id,
  });

  final String name;
  final String content;
  final String? id;
}

/// Validated, aggregated migration plan ready for atomic execution.
class PreparedMigration {
  const PreparedMigration({
    required this.transactions,
    required this.fileCount,
    this.isSkipped = false,
    this.skipReason,
  });

  factory PreparedMigration.skipped({required String reason}) {
    return PreparedMigration(
      transactions: const <ImportTransaction>[],
      fileCount: 0,
      isSkipped: true,
      skipReason: reason,
    );
  }

  factory PreparedMigration.empty() {
    return const PreparedMigration(
      transactions: <ImportTransaction>[],
      fileCount: 0,
    );
  }

  final List<ImportTransaction> transactions;
  final int fileCount;
  final bool isSkipped;
  final String? skipReason;
}

/// Orchestrates safe transactional migration of legacy monthly backups into
/// local storage and prepares a complete snapshot without data loss.
///
/// Invariants:
/// 1. Avoid resurrecting deletions: migration runs ONLY if no snapshots exist.
/// 2. Fail closed on unreadable/invalid data: all files and transactions are
///    validated before ANY database write occurs.
/// 3. Duplicate monthly backup names or duplicate months are ambiguous and abort.
/// 4. Merge without overwrites: imports rows atomically in a single aggregate
///    database transaction, skipping already-stored records.
/// 5. Never deletes or prunes files. Drive snapshot upload is avoided because
///    SnapshotDriveService.uploadSnapshot prunes automatically.
class LegacyMigrationUseCase {
  LegacyMigrationUseCase({
    required TransactionRepository repository,
    SnapshotDriveService? driveService,
    ExportSnapshotUseCase? exportSnapshotUseCase,
  })  : _repository = repository,
        _driveService = driveService,
        _exportSnapshotUseCase =
            exportSnapshotUseCase ?? ExportSnapshotUseCase(repository);

  final TransactionRepository _repository;
  final SnapshotDriveService? _driveService;
  final ExportSnapshotUseCase _exportSnapshotUseCase;

  static const int supportedSchema = 1;
  static const int maxTransactionsPerMonth = 10000;
  static const int maxTotalTransactions = 100000;
  static const int _maxNameLength = 50;
  static const int _maxNoteLength = 500;
  static const double _maxAmount = 1e12;

  static final RegExp _legacyFileNamePattern = RegExp(
    r'^expense-tracker-(\d{4})-(\d{2})\.json$',
  );

  /// Validates a single monthly backup document in memory without database side-effects.
  /// Throws [MigrationException] on any schema violation, unreadable row, or bad metadata.
  List<ImportTransaction> validateAndParseMonthlyJson({
    required String fileName,
    required String jsonText,
  }) {
    final Map<String, dynamic> document;
    try {
      final Object? decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw MigrationException(
          'File "$fileName" is not an Expense Tracker backup document.',
        );
      }
      document = decoded;
    } on FormatException {
      throw MigrationException('File "$fileName" is not readable as valid JSON.');
    } catch (e) {
      if (e is MigrationException) rethrow;
      throw MigrationException('File "$fileName" could not be read as JSON.');
    }

    final Object? app = document['app'];
    if (app is String && app != 'Expense Tracker') {
      throw MigrationException(
        'File "$fileName" was written by "$app", not Expense Tracker.',
      );
    }

    final Object? schema = document['schemaVersion'];
    if (schema is num && schema > supportedSchema) {
      throw MigrationException(
        'File "$fileName" schema version ($schema) is newer than supported ($supportedSchema).',
      );
    }

    final Object? period = document['period'];
    if (period is! Map<String, dynamic>) {
      throw MigrationException('File "$fileName" is missing valid period metadata.');
    }
    final Object? year = period['year'];
    final Object? month = period['month'];
    if (year is! int || month is! int || month < 1 || month > 12 || year < 1900 || year > 2200) {
      throw MigrationException('File "$fileName" has invalid year ($year) or month ($month).');
    }

    // Ensure filename month matches the internal period metadata if named according to convention
    final RegExpMatch? match = _legacyFileNamePattern.firstMatch(fileName);
    if (match != null) {
      final int fileYear = int.parse(match.group(1)!);
      final int fileMonth = int.parse(match.group(2)!);
      if (fileYear != year || fileMonth != month) {
        throw MigrationException(
          'File "$fileName" name indicates $fileYear-$fileMonth but content specifies $year-$month.',
        );
      }
    }

    final Object? rawTransactions = document['transactions'];
    if (rawTransactions is! List<Object?>) {
      throw MigrationException('File "$fileName" has invalid or missing transactions list.');
    }
    if (rawTransactions.length > maxTransactionsPerMonth) {
      throw MigrationException(
        'File "$fileName" contains ${rawTransactions.length} transactions, exceeding monthly limit ($maxTransactionsPerMonth).',
      );
    }

    final List<ImportTransaction> parsedRows = <ImportTransaction>[];
    for (int i = 0; i < rawTransactions.length; i++) {
      final Object? entry = rawTransactions[i];
      final ImportTransaction? row = _readTransaction(entry);
      if (row == null) {
        // Fail closed: unlike single-month import which skips unreadable rows,
        // migration strictly fails closed on invalid/unreadable rows before any DB write.
        throw MigrationException(
          'File "$fileName" contains unreadable or invalid transaction at row ${i + 1}. Aborting migration to protect data integrity.',
        );
      }
      parsedRows.add(row);
    }

    return parsedRows;
  }

  /// Dry-run validates a list of monthly backup files and constructs an aggregated migration plan.
  /// Throws [MigrationException] on duplicate filenames, duplicate months, or invalid data.
  PreparedMigration prepareFromFiles(
    List<LegacyFileEntry> files, {
    bool hasSnapshots = false,
  }) {
    if (hasSnapshots) {
      return PreparedMigration.skipped(
        reason:
            'Existing snapshot backups present. Legacy migration is only allowed when no snapshots exist to avoid resurrecting deleted records.',
      );
    }

    if (files.isEmpty) {
      return PreparedMigration.empty();
    }

    // Check duplicate file names (Drive can hold multiple files with identical names)
    final Set<String> seenNames = <String>{};
    for (final LegacyFileEntry file in files) {
      if (!seenNames.add(file.name)) {
        throw MigrationException(
          'Duplicate monthly backup file name detected: "${file.name}". Aborting migration due to ambiguous monthly backups.',
        );
      }
    }

    final Set<String> seenMonths = <String>{};
    final List<ImportTransaction> allTransactions = <ImportTransaction>[];

    for (final LegacyFileEntry file in files) {
      final List<ImportTransaction> rows = validateAndParseMonthlyJson(
        fileName: file.name,
        jsonText: file.content,
      );

      final RegExpMatch? match = _legacyFileNamePattern.firstMatch(file.name);
      final String monthKey;
      if (match != null) {
        monthKey = '${match.group(1)}-${match.group(2)}';
      } else {
        final Map<String, dynamic> doc =
            jsonDecode(file.content) as Map<String, dynamic>;
        final Map<String, dynamic> p = doc['period'] as Map<String, dynamic>;
        monthKey =
            '${p['year']}-${(p['month'] as int).toString().padLeft(2, '0')}';
      }

      if (!seenMonths.add(monthKey)) {
        throw MigrationException(
          'Duplicate monthly backups detected for month "$monthKey". Aborting migration due to ambiguous monthly backups.',
        );
      }

      allTransactions.addAll(rows);
    }

    if (allTransactions.length > maxTotalTransactions) {
      throw MigrationException(
        'Total transactions across all monthly backups (${allTransactions.length}) exceeds snapshot limit ($maxTotalTransactions).',
      );
    }

    return PreparedMigration(
      transactions: allTransactions,
      fileCount: files.length,
    );
  }

  /// Inspects Google Drive, checks snapshot absence, downloads legacy monthly files,
  /// and performs dry-run validation.
  Future<PreparedMigration> prepareFromDrive({String? folderName}) async {
    final SnapshotDriveService? drive = _driveService;
    if (drive == null) {
      throw MigrationException('SnapshotDriveService is not configured.');
    }

    // 1. Avoid resurrecting deletions: migrate ONLY IF NO SNAPSHOTS
    final List<Map<String, dynamic>> snapshots =
        await drive.listOwnedSnapshots(folderName: folderName);
    if (snapshots.isNotEmpty) {
      return PreparedMigration.skipped(
        reason:
            'Existing snapshots found (${snapshots.length}). Legacy migration skipped to avoid resurrecting deletions.',
      );
    }

    // 2. List legacy monthly backup files
    final List<Map<String, dynamic>> legacyFiles =
        await drive.listLegacyMonthlyBackups(folderName: folderName);
    if (legacyFiles.isEmpty) {
      return PreparedMigration.empty();
    }

    final Set<String> seenNames = <String>{};
    for (final Map<String, dynamic> file in legacyFiles) {
      final String name = file['name'] as String? ?? '';
      if (!seenNames.add(name)) {
        throw MigrationException(
          'Duplicate monthly backup file name detected in Drive: "$name". Ambiguous state; aborting migration.',
        );
      }
    }

    // 3. Download and dry-run validate all files before writing to DB
    final List<LegacyFileEntry> entries = <LegacyFileEntry>[];
    for (final Map<String, dynamic> file in legacyFiles) {
      final String id = file['id'] as String;
      final String name = file['name'] as String;
      final List<int> bytes = await drive.downloadFile(id);
      final String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        throw MigrationException(
          'File "$name" (id: $id) could not be decoded as UTF-8. Aborting migration.',
        );
      }
      entries.add(LegacyFileEntry(name: name, content: content, id: id));
    }

    return prepareFromFiles(entries, hasSnapshots: false);
  }

  /// Executes a prepared migration:
  /// 1. Merges rows atomically into local DB without overwriting existing data.
  /// 2. Prepares a complete snapshot of local state.
  /// 3. Leaves all files intact without deletion or pruning.
  Future<MigrationResult> executePrepared(
    PreparedMigration prepared, {
    DateTime? snapshotExportTime,
  }) async {
    if (prepared.isSkipped) {
      return MigrationResult.skipped(
        reason: prepared.skipReason ?? 'Migration skipped.',
      );
    }

    if (prepared.fileCount == 0 && prepared.transactions.isEmpty) {
      return MigrationResult.noLegacyFiles();
    }

    // Atomic aggregate single import for all months
    final ImportWriteResult writeResult =
        await _repository.importTransactions(prepared.transactions);

    // Prepare complete snapshot of the newly updated local database
    final SnapshotExport snapshot =
        await _exportSnapshotUseCase(now: snapshotExportTime);

    // ponytail: Drive snapshot upload deferred because SnapshotDriveService.uploadSnapshot unconditionally prunes; enable upload when safe non-pruning upload option is added.
    return MigrationResult.completed(
      filesProcessed: prepared.fileCount,
      importedCount: writeResult.imported,
      duplicatesCount: writeResult.duplicates,
      totalTransactions: prepared.transactions.length,
      preparedSnapshot: snapshot,
    );
  }

  /// Automatically orchestrates dry-run validation, atomic merge, and snapshot preparation.
  Future<MigrationResult> autoMigrate({
    String? folderName,
    Map<String, String>? localFiles,
    bool snapshotsExist = false,
    DateTime? snapshotExportTime,
  }) async {
    final PreparedMigration prepared;
    if (localFiles != null) {
      final List<LegacyFileEntry> entries = localFiles.entries
          .map((MapEntry<String, String> e) =>
              LegacyFileEntry(name: e.key, content: e.value))
          .toList();
      prepared = prepareFromFiles(entries, hasSnapshots: snapshotsExist);
    } else {
      prepared = await prepareFromDrive(folderName: folderName);
    }

    return executePrepared(prepared, snapshotExportTime: snapshotExportTime);
  }

  ImportTransaction? _readTransaction(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;

    final Object? rawType = entry['type'];
    if (rawType is! String || (rawType != 'income' && rawType != 'expense')) {
      return null;
    }

    final Object? rawAmount = entry['amount'];
    if (rawAmount is! num) return null;
    final double amount = rawAmount.toDouble();
    if (!amount.isFinite || amount <= 0 || amount > _maxAmount) return null;

    final Object? rawDate = entry['date'];
    if (rawDate is! String) return null;
    final DateTime? parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return null;

    final String? category = _readName(entry['category'], _maxNameLength);
    if (category == null) return null;

    final Object? rawSubcategory = entry['subcategory'];
    final String? subcategoryName = _readName(rawSubcategory, _maxNameLength);
    if (_hasValue(rawSubcategory) && subcategoryName == null) return null;

    final Object? rawNote = entry['note'];
    final String? note = _readName(rawNote, _maxNoteLength);
    if (_hasValue(rawNote) && note == null) return null;

    return ImportTransaction(
      date: DateTime(parsed.year, parsed.month, parsed.day),
      type: rawType,
      amount: amount,
      categoryName: category,
      subcategoryName: subcategoryName,
      note: note,
    );
  }

  static bool _hasValue(Object? value) =>
      value != null && value is String && value.trim().isNotEmpty;

  static String? _readName(Object? value, int limit) {
    if (value == null) return null;
    if (value is! String) return null;

    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > limit) return null;
    if (trimmed.runes.any(_isUnsafeRune)) return null;
    return trimmed;
  }

  static bool _isUnsafeRune(int rune) {
    const int delete = 0x7F;
    const int c1Start = 0x80;
    const int c1End = 0x9F;
    const int zeroWidthSpace = 0x200B;
    const int leftToRightMark = 0x200E;
    const int rightToLeftMark = 0x200F;
    const int arabicLetterMark = 0x61C;
    const int leftToRightEmbedding = 0x202A;
    const int rightToLeftOverride = 0x202E;
    const int leftToRightIsolate = 0x2066;
    const int rightToLeftIsolate = 0x2069;
    const int byteOrderMark = 0xFEFF;

    if (rune < 0x20) return true;
    if (rune == delete) return true;
    if (rune >= c1Start && rune <= c1End) return true;
    if (rune == arabicLetterMark) return true;
    if (rune >= zeroWidthSpace && rune <= leftToRightMark) return true;
    if (rune == rightToLeftMark) return true;
    if (rune >= leftToRightEmbedding && rune <= rightToLeftOverride) return true;
    if (rune >= leftToRightIsolate && rune <= rightToLeftIsolate) return true;
    if (rune == byteOrderMark) return true;
    return false;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:expense_tracker/data/services/snapshot_coordinator.dart';
import 'package:expense_tracker/data/services/snapshot_drive_service.dart';
import 'package:expense_tracker/domain/usecases/export_snapshot_usecase.dart';
import 'package:expense_tracker/domain/usecases/import_snapshot_usecase.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:expense_tracker/data/services/file_picker_service.dart';
import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:expense_tracker/domain/usecases/export_csv_usecase.dart';
import 'package:expense_tracker/domain/usecases/export_pdf_usecase.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';

/// Plain (non-code-generated) providers so adding this feature does not require
/// re-running build_runner.

final googleDriveServiceProvider = Provider<GoogleDriveService>(
  (Ref ref) => GoogleDriveService.instance,
);

final snapshotCoordinatorProvider = Provider<SnapshotCoordinator>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  final drive = SnapshotDriveService(
    client: client,
    headers: ref.watch(googleDriveServiceProvider).snapshotHeaders,
  );
  final repository = ref.watch(transactionRepositoryProvider);
  return SnapshotCoordinator(
    drive,
    ExportSnapshotUseCase(repository),
    ImportSnapshotUseCase(repository),
  );
});

class SnapshotActionController extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() => const AsyncData(null);

  Future<void> run({required bool backup}) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final coordinator = ref.read(snapshotCoordinatorProvider);
      if (backup) return 'Backup created: ${await coordinator.backup()}';
      final result = await coordinator.sync();
      return 'Sync complete: ${result.imported} imported, ${result.duplicates} already present.';
    });
  }
}

final snapshotActionProvider =
    NotifierProvider<SnapshotActionController, AsyncValue<String?>>(
        SnapshotActionController.new);

/// The signed-in Google account, or `null` while signed out.
///
/// Emits an error if the Google integration has not been configured yet.
final googleAccountProvider = StreamProvider<GoogleSignInAccount?>(
  (Ref ref) => ref.watch(googleDriveServiceProvider).accountChanges(),
);

/// The PDF report reads the same repository as the Drive backup, but writes
/// nothing: it is a local file handed to the share sheet.
final exportPdfUseCaseProvider = Provider<ExportPdfUseCase>(
  (Ref ref) => ExportPdfUseCase(ref.watch(transactionRepositoryProvider)),
);

/// The same range as the PDF, as rows a spreadsheet can read: also local, and
/// also no Google account.
final exportCsvUseCaseProvider = Provider<ExportCsvUseCase>(
  (Ref ref) => ExportCsvUseCase(ref.watch(transactionRepositoryProvider)),
);

/// Reads a backup file the user picks through Android's file chooser.
final filePickerServiceProvider = Provider<FilePickerService>(
  (Ref ref) => FilePickerService(),
);

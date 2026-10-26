import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:expense_tracker/data/services/file_picker_service.dart';
import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:expense_tracker/domain/usecases/export_month_usecase.dart';
import 'package:expense_tracker/domain/usecases/export_pdf_usecase.dart';
import 'package:expense_tracker/domain/usecases/import_month_usecase.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';

/// Plain (non-code-generated) providers so adding this feature does not require
/// re-running build_runner.

final googleDriveServiceProvider = Provider<GoogleDriveService>(
  (Ref ref) => GoogleDriveService.instance,
);

/// The signed-in Google account, or `null` while signed out.
///
/// Emits an error if the Google integration has not been configured yet.
final googleAccountProvider = StreamProvider<GoogleSignInAccount?>(
  (Ref ref) => ref.watch(googleDriveServiceProvider).accountChanges(),
);

final exportMonthUseCaseProvider = Provider<ExportMonthUseCase>(
  (Ref ref) => ExportMonthUseCase(ref.watch(transactionRepositoryProvider)),
);

/// The PDF report reads the same repository as the Drive backup, but writes
/// nothing: it is a local file handed to the share sheet.
final exportPdfUseCaseProvider = Provider<ExportPdfUseCase>(
  (Ref ref) => ExportPdfUseCase(ref.watch(transactionRepositoryProvider)),
);

/// Reads a backup file the user picks through Android's file chooser.
final filePickerServiceProvider = Provider<FilePickerService>(
  (Ref ref) => FilePickerService(),
);

/// Reads a backup — from a file or from Drive — and writes its rows.
final importMonthUseCaseProvider = Provider<ImportMonthUseCase>(
  (Ref ref) => ImportMonthUseCase(ref.watch(transactionRepositoryProvider)),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:expense_tracker/data/services/google_drive_service.dart';
import 'package:expense_tracker/domain/usecases/export_month_usecase.dart';
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

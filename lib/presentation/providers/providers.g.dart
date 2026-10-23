// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$databaseHash() => r'd7a35a83ad0e3d2e5c3a40b438bc9be186d6af93';

/// See also [database].
@ProviderFor(database)
final databaseProvider = AutoDisposeProvider<AppDatabase>.internal(
  database,
  name: r'databaseProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$databaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef DatabaseRef = AutoDisposeProviderRef<AppDatabase>;
String _$transactionRepositoryHash() =>
    r'4efcfcac3fe9e584982b1690bd37626f11416ac6';

/// See also [transactionRepository].
@ProviderFor(transactionRepository)
final transactionRepositoryProvider =
    AutoDisposeProvider<TransactionRepository>.internal(
  transactionRepository,
  name: r'transactionRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$transactionRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef TransactionRepositoryRef
    = AutoDisposeProviderRef<TransactionRepository>;
String _$getTransactionsUseCaseHash() =>
    r'2ee618e7f9c5e810aa16671da25a8f187378c2ad';

/// See also [getTransactionsUseCase].
@ProviderFor(getTransactionsUseCase)
final getTransactionsUseCaseProvider =
    AutoDisposeProvider<GetTransactionsUseCase>.internal(
  getTransactionsUseCase,
  name: r'getTransactionsUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$getTransactionsUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef GetTransactionsUseCaseRef
    = AutoDisposeProviderRef<GetTransactionsUseCase>;
String _$getTransactionsByDateRangeUseCaseHash() =>
    r'811a4154538a85a643bb2d0fbc18ea5b7b37d9c5';

/// See also [getTransactionsByDateRangeUseCase].
@ProviderFor(getTransactionsByDateRangeUseCase)
final getTransactionsByDateRangeUseCaseProvider =
    AutoDisposeProvider<GetTransactionsByDateRangeUseCase>.internal(
  getTransactionsByDateRangeUseCase,
  name: r'getTransactionsByDateRangeUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$getTransactionsByDateRangeUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef GetTransactionsByDateRangeUseCaseRef
    = AutoDisposeProviderRef<GetTransactionsByDateRangeUseCase>;
String _$addTransactionUseCaseHash() =>
    r'e0eaae22c845b42ef7345010aef37a616b585636';

/// See also [addTransactionUseCase].
@ProviderFor(addTransactionUseCase)
final addTransactionUseCaseProvider =
    AutoDisposeProvider<AddTransactionUseCase>.internal(
  addTransactionUseCase,
  name: r'addTransactionUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$addTransactionUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AddTransactionUseCaseRef
    = AutoDisposeProviderRef<AddTransactionUseCase>;
String _$updateTransactionUseCaseHash() =>
    r'8e9ff3a2f57e7431f3d0be68361c664601c2f746';

/// See also [updateTransactionUseCase].
@ProviderFor(updateTransactionUseCase)
final updateTransactionUseCaseProvider =
    AutoDisposeProvider<UpdateTransactionUseCase>.internal(
  updateTransactionUseCase,
  name: r'updateTransactionUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$updateTransactionUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef UpdateTransactionUseCaseRef
    = AutoDisposeProviderRef<UpdateTransactionUseCase>;
String _$deleteTransactionUseCaseHash() =>
    r'dcab222081aa88b1ba2aaae70a29f4af7a038432';

/// See also [deleteTransactionUseCase].
@ProviderFor(deleteTransactionUseCase)
final deleteTransactionUseCaseProvider =
    AutoDisposeProvider<DeleteTransactionUseCase>.internal(
  deleteTransactionUseCase,
  name: r'deleteTransactionUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$deleteTransactionUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef DeleteTransactionUseCaseRef
    = AutoDisposeProviderRef<DeleteTransactionUseCase>;
String _$getSummaryUseCaseHash() => r'7d4802da7c6c68e4b61891869f2feeec181f3798';

/// See also [getSummaryUseCase].
@ProviderFor(getSummaryUseCase)
final getSummaryUseCaseProvider =
    AutoDisposeProvider<GetSummaryUseCase>.internal(
  getSummaryUseCase,
  name: r'getSummaryUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$getSummaryUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef GetSummaryUseCaseRef = AutoDisposeProviderRef<GetSummaryUseCase>;
String _$transactionsStreamHash() =>
    r'493e5bf6d0f342335da3b82a0d540e513f990391';

/// See also [transactionsStream].
@ProviderFor(transactionsStream)
final transactionsStreamProvider =
    AutoDisposeStreamProvider<List<TransactionEntity>>.internal(
  transactionsStream,
  name: r'transactionsStreamProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$transactionsStreamHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef TransactionsStreamRef
    = AutoDisposeStreamProviderRef<List<TransactionEntity>>;
String _$summaryHash() => r'91155ad6d5747f0e26133e436d7e4ea315025f75';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [summary].
@ProviderFor(summary)
const summaryProvider = SummaryFamily();

/// See also [summary].
class SummaryFamily extends Family<AsyncValue<SummaryResult>> {
  /// See also [summary].
  const SummaryFamily();

  /// See also [summary].
  SummaryProvider call({
    DateTime? start,
    DateTime? end,
  }) {
    return SummaryProvider(
      start: start,
      end: end,
    );
  }

  @override
  SummaryProvider getProviderOverride(
    covariant SummaryProvider provider,
  ) {
    return call(
      start: provider.start,
      end: provider.end,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'summaryProvider';
}

/// See also [summary].
class SummaryProvider extends AutoDisposeFutureProvider<SummaryResult> {
  /// See also [summary].
  SummaryProvider({
    DateTime? start,
    DateTime? end,
  }) : this._internal(
          (ref) => summary(
            ref as SummaryRef,
            start: start,
            end: end,
          ),
          from: summaryProvider,
          name: r'summaryProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$summaryHash,
          dependencies: SummaryFamily._dependencies,
          allTransitiveDependencies: SummaryFamily._allTransitiveDependencies,
          start: start,
          end: end,
        );

  SummaryProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.start,
    required this.end,
  }) : super.internal();

  final DateTime? start;
  final DateTime? end;

  @override
  Override overrideWith(
    FutureOr<SummaryResult> Function(SummaryRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SummaryProvider._internal(
        (ref) => create(ref as SummaryRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        start: start,
        end: end,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<SummaryResult> createElement() {
    return _SummaryProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SummaryProvider && other.start == start && other.end == end;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, start.hashCode);
    hash = _SystemHash.combine(hash, end.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin SummaryRef on AutoDisposeFutureProviderRef<SummaryResult> {
  /// The parameter `start` of this provider.
  DateTime? get start;

  /// The parameter `end` of this provider.
  DateTime? get end;
}

class _SummaryProviderElement
    extends AutoDisposeFutureProviderElement<SummaryResult> with SummaryRef {
  _SummaryProviderElement(super.provider);

  @override
  DateTime? get start => (origin as SummaryProvider).start;
  @override
  DateTime? get end => (origin as SummaryProvider).end;
}

String _$watchBudgetsUseCaseHash() =>
    r'a688d88aff0984f37e774c44d830b3d70a43c2bc';

/// See also [watchBudgetsUseCase].
@ProviderFor(watchBudgetsUseCase)
final watchBudgetsUseCaseProvider =
    AutoDisposeProvider<WatchBudgetsUseCase>.internal(
  watchBudgetsUseCase,
  name: r'watchBudgetsUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$watchBudgetsUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef WatchBudgetsUseCaseRef = AutoDisposeProviderRef<WatchBudgetsUseCase>;
String _$setBudgetUseCaseHash() => r'bdaca0c4c77cc5954a59f5c38d379cb3f3a871d2';

/// See also [setBudgetUseCase].
@ProviderFor(setBudgetUseCase)
final setBudgetUseCaseProvider = AutoDisposeProvider<SetBudgetUseCase>.internal(
  setBudgetUseCase,
  name: r'setBudgetUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$setBudgetUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef SetBudgetUseCaseRef = AutoDisposeProviderRef<SetBudgetUseCase>;
String _$clearBudgetUseCaseHash() =>
    r'47c17fd94b248f4b14d33017c3cdf7e658b15e25';

/// See also [clearBudgetUseCase].
@ProviderFor(clearBudgetUseCase)
final clearBudgetUseCaseProvider =
    AutoDisposeProvider<ClearBudgetUseCase>.internal(
  clearBudgetUseCase,
  name: r'clearBudgetUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$clearBudgetUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ClearBudgetUseCaseRef = AutoDisposeProviderRef<ClearBudgetUseCase>;
String _$budgetsHash() => r'aaf645b4e322d24e5e7dff37d928f7a28dd3d92c';

/// The ceilings the user has set, live: a sheet that writes one updates the
/// bars behind it without a refresh.
///
/// Copied from [budgets].
@ProviderFor(budgets)
final budgetsProvider =
    AutoDisposeStreamProvider<List<CategoryBudget>>.internal(
  budgets,
  name: r'budgetsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$budgetsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef BudgetsRef = AutoDisposeStreamProviderRef<List<CategoryBudget>>;
String _$watchRecurringTemplatesUseCaseHash() =>
    r'd9d8def121c24382b01cf6f9e0d67723eecb7341';

/// See also [watchRecurringTemplatesUseCase].
@ProviderFor(watchRecurringTemplatesUseCase)
final watchRecurringTemplatesUseCaseProvider =
    AutoDisposeProvider<WatchRecurringTemplatesUseCase>.internal(
  watchRecurringTemplatesUseCase,
  name: r'watchRecurringTemplatesUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$watchRecurringTemplatesUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef WatchRecurringTemplatesUseCaseRef
    = AutoDisposeProviderRef<WatchRecurringTemplatesUseCase>;
String _$addRecurringTemplateUseCaseHash() =>
    r'0466da9ff23849ecde728d27f7d45f833f5ea8ff';

/// See also [addRecurringTemplateUseCase].
@ProviderFor(addRecurringTemplateUseCase)
final addRecurringTemplateUseCaseProvider =
    AutoDisposeProvider<AddRecurringTemplateUseCase>.internal(
  addRecurringTemplateUseCase,
  name: r'addRecurringTemplateUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$addRecurringTemplateUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AddRecurringTemplateUseCaseRef
    = AutoDisposeProviderRef<AddRecurringTemplateUseCase>;
String _$setRecurringTemplateActiveUseCaseHash() =>
    r'2478cb1b4615c80364a058e7c6ecce0c72ac4b2d';

/// See also [setRecurringTemplateActiveUseCase].
@ProviderFor(setRecurringTemplateActiveUseCase)
final setRecurringTemplateActiveUseCaseProvider =
    AutoDisposeProvider<SetRecurringTemplateActiveUseCase>.internal(
  setRecurringTemplateActiveUseCase,
  name: r'setRecurringTemplateActiveUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$setRecurringTemplateActiveUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef SetRecurringTemplateActiveUseCaseRef
    = AutoDisposeProviderRef<SetRecurringTemplateActiveUseCase>;
String _$deleteRecurringTemplateUseCaseHash() =>
    r'1172b24b3f22559df227f23330595a1d4591c747';

/// See also [deleteRecurringTemplateUseCase].
@ProviderFor(deleteRecurringTemplateUseCase)
final deleteRecurringTemplateUseCaseProvider =
    AutoDisposeProvider<DeleteRecurringTemplateUseCase>.internal(
  deleteRecurringTemplateUseCase,
  name: r'deleteRecurringTemplateUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$deleteRecurringTemplateUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef DeleteRecurringTemplateUseCaseRef
    = AutoDisposeProviderRef<DeleteRecurringTemplateUseCase>;
String _$applyRecurringTemplatesUseCaseHash() =>
    r'384692ecd5e593474eeb684c41a57f73563dc2eb';

/// See also [applyRecurringTemplatesUseCase].
@ProviderFor(applyRecurringTemplatesUseCase)
final applyRecurringTemplatesUseCaseProvider =
    AutoDisposeProvider<ApplyRecurringTemplatesUseCase>.internal(
  applyRecurringTemplatesUseCase,
  name: r'applyRecurringTemplatesUseCaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$applyRecurringTemplatesUseCaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ApplyRecurringTemplatesUseCaseRef
    = AutoDisposeProviderRef<ApplyRecurringTemplatesUseCase>;
String _$recurringTemplatesHash() =>
    r'83abdbf2f91776e5ded486c9873865b87f78daef';

/// The templates, live, so switching one off leaves the list telling the truth.
///
/// Copied from [recurringTemplates].
@ProviderFor(recurringTemplates)
final recurringTemplatesProvider =
    AutoDisposeStreamProvider<List<RecurringTemplateEntity>>.internal(
  recurringTemplates,
  name: r'recurringTemplatesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$recurringTemplatesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef RecurringTemplatesRef
    = AutoDisposeStreamProviderRef<List<RecurringTemplateEntity>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

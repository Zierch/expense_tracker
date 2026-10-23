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
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

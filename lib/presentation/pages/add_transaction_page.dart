import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:go_router/go_router.dart';

class AddTransactionPage extends ConsumerStatefulWidget {
  final int? transactionId;

  const AddTransactionPage({super.key, this.transactionId});

  @override
  ConsumerState<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  static const int _maxAmountLength = 12; // up to 999,999,999,999

  final _formKey = GlobalKey<FormState>();
  String _type = 'expense';
  final _amountController = TextEditingController();
  int? _selectedCategoryId;
  int? _selectedSubcategoryId;
  final _noteController = TextEditingController();
  DateTime _date = _dateOnly(DateTime.now());
  bool _isLoading = false;

  List<Category> _categories = [];
  List<Subcategory> _subcategories = [];

  /// Drops the time of day. The stored value is a calendar day, never an instant:
  /// a fresh page used `DateTime.now()` while the date picker returns midnight, and
  /// that mixture made one day behave differently depending on whether the picker
  /// had been opened.
  ///
  /// Every assignment to `_date` goes through here, so the field is date-only by
  /// construction. The call at the insert is therefore a guard against a future
  /// assignment site rather than a conversion that is needed today.
  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  void initState() {
    super.initState();
    _loadCategories();
    if (widget.transactionId != null) {
      _loadTransaction();
    }
  }

  Future<void> _loadCategories() async {
    final db = ref.read(databaseProvider);
    final categories = await db.getCategories(type: _type);
    setState(() {
      _categories = categories;
      // Reset subcategory when categories change
      _selectedSubcategoryId = null;
      // Auto-select first category if none selected or current not in list
      if (_categories.isNotEmpty) {
        if (_selectedCategoryId == null ||
            !_categories.any((c) => c.id == _selectedCategoryId)) {
          _selectedCategoryId = _categories.first.id;
        }
      }
    });
    if (_categories.isNotEmpty && _selectedCategoryId != null) {
      _loadSubcategories();
    }
  }

  Future<void> _loadSubcategories() async {
    if (_selectedCategoryId == null) return;
    final db = ref.read(databaseProvider);
    final subcategories = await db.getSubcategories(_selectedCategoryId!);
    setState(() {
      _subcategories = subcategories;
      // Reset subcategory selection if current value not in new list
      if (_selectedSubcategoryId != null &&
          !_subcategories.any((s) => s.id == _selectedSubcategoryId)) {
        _selectedSubcategoryId = null;
      }
    });
  }

  Future<void> _loadTransaction() async {
    final transactions = await ref.read(getTransactionsUseCaseProvider).call();
    final transaction = transactions.firstWhere(
      (t) => t.id == widget.transactionId,
      orElse: () => throw Exception('Transaction not found'),
    );
    setState(() {
      _type = transaction.type;
      _amountController.text = transaction.amount.toStringAsFixed(0);
      _selectedCategoryId = transaction.categoryId;
      _selectedSubcategoryId = transaction.subcategoryId;
      _noteController.text = transaction.note ?? '';
      _date = _dateOnly(transaction.date);
    });
    _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.transactionId == null ? 'Add Transaction' : 'Edit Transaction'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildTypeSelector(),
            const SizedBox(height: 16),
            _buildAmountField(),
            const SizedBox(height: 16),
            _buildCategorySelector(),
            const SizedBox(height: 16),
            if (_subcategories.isNotEmpty) _buildSubcategorySelector(),
            if (_subcategories.isNotEmpty) const SizedBox(height: 16),
            _buildDatePicker(),
            const SizedBox(height: 16),
            _buildNoteField(),
            const SizedBox(height: 24),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'expense', label: Text('Expense'), icon: Icon(Icons.arrow_upward)),
        ButtonSegment(value: 'income', label: Text('Income'), icon: Icon(Icons.arrow_downward)),
      ],
      selected: {_type},
      onSelectionChanged: (set) {
        setState(() => _type = set.first);
        _selectedCategoryId = null;
        _selectedSubcategoryId = null;
        _loadCategories();
      },
    );
  }

  Widget _buildAmountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _amountController,
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: 'Rp ',
            border: OutlineInputBorder(),
            hintText: '0',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_maxAmountLength),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) return 'Enter amount';
            final amount = double.tryParse(value);
            if (amount == null || amount <= 0) return 'Invalid amount';
            return null;
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _appendAmount('0'),
                icon: const Icon(Icons.numbers, size: 18),
                label: const Text('0'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _appendAmount('00'),
                icon: const Icon(Icons.numbers, size: 18),
                label: const Text('00'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _appendAmount('000'),
                icon: const Icon(Icons.numbers, size: 18),
                label: const Text('000'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _appendAmount(String text) {
    final current = _amountController.text;
    final next = current == '0' ? text : current + text;
    if (next.length > _maxAmountLength) return;
    _amountController.text = next;
    _amountController.selection = TextSelection.fromPosition(
      TextPosition(offset: next.length),
    );
  }

  Widget _buildCategorySelector() {
    String categoryName = _type == 'income' ? 'Income' : 'Expense';
    if (_categories.isNotEmpty) {
      final match = _categories.where((c) => c.id == _selectedCategoryId);
      categoryName = match.isNotEmpty ? match.first.name : _categories.first.name;
    }
    final hintColor = Theme.of(context).textTheme.bodySmall?.color;

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Category',
        border: OutlineInputBorder(),
        helperText: 'Set by the type above',
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(categoryName, style: const TextStyle(fontSize: 16)),
          Icon(Icons.lock_outline, size: 16, color: hintColor),
        ],
      ),
    );
  }

  Widget _buildSubcategorySelector() {
    return DropdownButtonFormField<int?>(
      value: _selectedSubcategoryId,
      decoration: const InputDecoration(
        labelText: 'Subcategory',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('None')),
        ..._subcategories.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
      ],
      onChanged: (value) => setState(() => _selectedSubcategoryId = value),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: _pickDate,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today),
        ),
        child: Text(
          DateFormat('dd MMMM yyyy', 'en_US').format(_date),
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = _dateOnly(picked));
  }

  Widget _buildNoteField() {
    return TextFormField(
      controller: _noteController,
      decoration: const InputDecoration(
        labelText: 'Note (optional)',
        border: OutlineInputBorder(),
        hintText: 'Add note...',
      ),
      maxLines: 3,
    );
  }

  Widget _buildSaveButton() {
    return FilledButton.icon(
      onPressed: _isLoading ? null : _saveTransaction,
      icon: _isLoading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.save),
      label: Text(widget.transactionId == null ? 'Save' : 'Update'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate() || _selectedCategoryId == null) return;

    setState(() => _isLoading = true);

    try {
      final transaction = TransactionEntity(
        id: widget.transactionId ?? 0,
        type: _type,
        amount: double.parse(_amountController.text),
        categoryId: _selectedCategoryId!,
        subcategoryId: _selectedSubcategoryId,
        note: _noteController.text.isEmpty ? null : _noteController.text,
        date: _dateOnly(_date),
        createdAt: DateTime.now(),
      );

      if (widget.transactionId == null) {
        await ref.read(addTransactionUseCaseProvider).call(transaction);
      } else {
        await ref.read(updateTransactionUseCaseProvider).call(transaction);
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

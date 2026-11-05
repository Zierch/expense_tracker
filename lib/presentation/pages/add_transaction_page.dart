import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';
import 'package:expense_tracker/presentation/widgets/idr_amount_input.dart';
import 'package:go_router/go_router.dart';

class AddTransactionPage extends ConsumerStatefulWidget {
  final int? transactionId;

  const AddTransactionPage({super.key, this.transactionId});

  @override
  ConsumerState<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'expense';
  final _amountController = TextEditingController();
  int? _selectedCategoryId;
  int? _selectedSubcategoryId;
  final _noteController = TextEditingController();
  DateTime _date = _dateOnly(DateTime.now());
  bool _isLoading = false;

  /// The creation time of the row being edited, kept so an edit does not restamp it.
  ///
  /// Null while adding. Creation time is not a field the form owns, so until the row
  /// arrives the page has nothing truthful to write — which is why the save button stays
  /// disabled until this is set (see [_buildSaveButton]) and the fallback at the insert is
  /// only ever reached while adding.
  DateTime? _createdAt;

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
    // One loader, not two. An edit has to know which type its row is before it
    // asks for categories, and asking first with the default type raced the row's
    // own load; `_loadTransaction` asks once the type is known.
    if (widget.transactionId != null) {
      _loadTransaction();
    } else {
      _loadCategories();
    }
  }

  Future<void> _loadCategories() async {
    final db = ref.read(databaseProvider);
    final categories = await db.getCategories(type: _type);
    // The read can outlive the page: popping straight back out of an edit unmounts
    // this before the rows arrive, and the loads now chain, which lengthens that
    // window rather than closing it.
    if (!mounted) return;
    setState(() {
      _categories = categories;
      // Auto-select first category if none selected or current not in list
      if (_categories.isNotEmpty) {
        if (_selectedCategoryId == null ||
            !_categories.any((c) => c.id == _selectedCategoryId)) {
          _selectedCategoryId = _categories.first.id;
          // The subcategory belonged to the category being replaced, so it is
          // either gone with it or belongs to another category. Only when the
          // category actually changes, though: clearing it on every load is what
          // used to wipe the subcategory an edit had just restored.
          _selectedSubcategoryId = null;
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
    if (!mounted) return;
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
      _amountController.text = formatIdrAmount(transaction.amount);
      _selectedCategoryId = transaction.categoryId;
      _selectedSubcategoryId = transaction.subcategoryId;
      _noteController.text = transaction.note ?? '';
      _date = _dateOnly(transaction.date);
      _createdAt = transaction.createdAt;
    });
    // After the row, so the categories are the ones its subcategory belongs to.
    await _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Design tokens from DESIGN.md
    final Color backgroundColor =
        isDark ? const Color(0xFF101916) : const Color(0xFFF4F6F8);
    final Color surfaceColor =
        isDark ? const Color(0xFF1B2924) : const Color(0xFFFFFFFF);
    final Color elevatedColor =
        isDark ? const Color(0xFF263A30) : const Color(0xFFFFFFFF);
    final Color borderColor =
        isDark ? const Color(0xFF31443A) : const Color(0xFFE5E7EB);
    final Color textColor =
        isDark ? const Color(0xFFEDF7F1) : const Color(0xFF111827);
    final Color mutedColor =
        isDark ? const Color(0xFFA8BDB3) : const Color(0xFF6B7280);
    final Color primaryColor =
        isDark ? const Color(0xFF83DFB7) : const Color(0xFF0E5A44);
    final Color onPrimaryColor =
        isDark ? const Color(0xFF10291F) : const Color(0xFFFFFFFF);
    final Color activeSegmentColor =
        isDark ? const Color(0xFF244239) : const Color(0xFFD1FAE5);
    final Color activeSegmentTextColor =
        isDark ? const Color(0xFF83DFB7) : const Color(0xFF0E5A44);
    final Color errorColor =
        isDark ? const Color(0xFFFF9393) : Theme.of(context).colorScheme.error;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.transactionId == null ? 'Add Transaction' : 'Edit Transaction',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        leading: BackButton(color: textColor),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            _buildTypeSelector(
              surfaceColor: surfaceColor,
              borderColor: borderColor,
              activeSegmentColor: activeSegmentColor,
              activeSegmentTextColor: activeSegmentTextColor,
              mutedColor: mutedColor,
            ),
            const SizedBox(height: 16),
            _buildAmountField(
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
              textColor: textColor,
              mutedColor: mutedColor,
              primaryColor: primaryColor,
              errorColor: errorColor,
            ),
            const SizedBox(height: 16),
            _buildCategorySelector(
              surfaceColor: surfaceColor,
              borderColor: borderColor,
              textColor: textColor,
              mutedColor: mutedColor,
            ),
            const SizedBox(height: 16),
            if (_subcategories.isNotEmpty) ...[
              _buildSubcategorySelector(
                elevatedColor: elevatedColor,
                surfaceColor: surfaceColor,
                borderColor: borderColor,
                textColor: textColor,
                mutedColor: mutedColor,
                primaryColor: primaryColor,
              ),
              const SizedBox(height: 16),
            ],
            _buildDatePicker(
              surfaceColor: surfaceColor,
              borderColor: borderColor,
              textColor: textColor,
              mutedColor: mutedColor,
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 16),
            _buildNoteField(
              surfaceColor: surfaceColor,
              borderColor: borderColor,
              textColor: textColor,
              mutedColor: mutedColor,
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 24),
            _buildSaveButton(
              isDark: isDark,
              primaryColor: primaryColor,
              onPrimaryColor: onPrimaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelector({
    required Color surfaceColor,
    required Color borderColor,
    required Color activeSegmentColor,
    required Color activeSegmentTextColor,
    required Color mutedColor,
  }) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'expense',
          label: Text('Expense'),
          icon: Icon(Icons.arrow_upward_rounded),
        ),
        ButtonSegment(
          value: 'income',
          label: Text('Income'),
          icon: Icon(Icons.arrow_downward_rounded),
        ),
      ],
      selected: {_type},
      onSelectionChanged: (set) {
        setState(() => _type = set.first);
        _selectedCategoryId = null;
        _selectedSubcategoryId = null;
        _loadCategories();
      },
      showSelectedIcon: true,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return activeSegmentColor;
          }
          return surfaceColor;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return activeSegmentTextColor;
          }
          return mutedColor;
        }),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: borderColor),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildAmountField({
    required bool isDark,
    required Color surfaceColor,
    required Color borderColor,
    required Color textColor,
    required Color mutedColor,
    required Color primaryColor,
    required Color errorColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _amountController,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
          decoration: InputDecoration(
            labelText: 'Amount',
            labelStyle: TextStyle(
              fontSize: 14,
              color: mutedColor,
              fontWeight: FontWeight.w500,
            ),
            floatingLabelStyle: TextStyle(
              fontSize: 14,
              color: primaryColor,
              fontWeight: FontWeight.w600,
            ),
            // Decoration, not value: "Rp. " cannot be typed over or deleted, and
            // it is on screen before the first digit arrives.
            prefixText: 'Rp. ',
            prefixStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            hintText: '0',
            hintStyle: TextStyle(color: mutedColor, fontSize: 20),
            filled: true,
            fillColor: surfaceColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: primaryColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: errorColor),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: errorColor, width: 2),
            ),
            errorStyle: TextStyle(color: errorColor, fontSize: 12),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[IdrAmountInputFormatter()],
          validator: (String? value) {
            final double? amount = parseIdrAmount(value ?? '');
            if (amount == null) return 'Enter amount';
            if (amount <= 0) return 'Invalid amount';
            return null;
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildQuickAmountButton('0', isDark, surfaceColor, borderColor, textColor),
            const SizedBox(width: 8),
            _buildQuickAmountButton('00', isDark, surfaceColor, borderColor, textColor),
            const SizedBox(width: 8),
            _buildQuickAmountButton('000', isDark, surfaceColor, borderColor, textColor),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickAmountButton(
    String digits,
    bool isDark,
    Color surfaceColor,
    Color borderColor,
    Color textColor,
  ) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () => _appendAmount(digits),
        icon: Text(
          '#',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFF83DFB7) : const Color(0xFF10B981),
          ),
        ),
        label: Text(digits),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          minimumSize: Size.zero,
          backgroundColor: surfaceColor,
          foregroundColor: textColor,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildCategorySelector({
    required Color surfaceColor,
    required Color borderColor,
    required Color textColor,
    required Color mutedColor,
  }) {
    String categoryName = _type == 'income' ? 'Income' : 'Expense';
    if (_categories.isNotEmpty) {
      final match = _categories.where((c) => c.id == _selectedCategoryId);
      categoryName = match.isNotEmpty ? match.first.name : _categories.first.name;
    }

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Category',
        labelStyle: TextStyle(
          fontSize: 14,
          color: mutedColor,
          fontWeight: FontWeight.w500,
        ),
        helperText: 'Set by the type above',
        helperStyle: TextStyle(color: mutedColor, fontSize: 12),
        filled: true,
        fillColor: surfaceColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            categoryName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          Icon(Icons.lock_outline_rounded, size: 18, color: mutedColor),
        ],
      ),
    );
  }

  Widget _buildSubcategorySelector({
    required Color surfaceColor,
    required Color elevatedColor,
    required Color borderColor,
    required Color textColor,
    required Color mutedColor,
    required Color primaryColor,
  }) {
    return DropdownButtonFormField<int?>(
      value: _selectedSubcategoryId,
      dropdownColor: elevatedColor,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: mutedColor),
      style: TextStyle(
        fontSize: 16,
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: 'Subcategory',
        labelStyle: TextStyle(
          fontSize: 14,
          color: mutedColor,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 14,
          color: primaryColor,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: surfaceColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
      items: [
        DropdownMenuItem(
          value: null,
          child: Text('None', style: TextStyle(color: textColor)),
        ),
        ..._subcategories.map(
          (s) => DropdownMenuItem(
            value: s.id,
            child: Text(s.name, style: TextStyle(color: textColor)),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _selectedSubcategoryId = value),
    );
  }

  Widget _buildDatePicker({
    required Color surfaceColor,
    required Color borderColor,
    required Color textColor,
    required Color mutedColor,
    required Color primaryColor,
  }) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date',
          labelStyle: TextStyle(
            fontSize: 14,
            color: mutedColor,
            fontWeight: FontWeight.w500,
          ),
          floatingLabelStyle: TextStyle(
            fontSize: 14,
            color: primaryColor,
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: surfaceColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          suffixIcon:
              Icon(Icons.calendar_today_rounded, size: 20, color: mutedColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: primaryColor, width: 2),
          ),
        ),
        child: Text(
          DateFormat('dd MMMM yyyy', 'en_US').format(_date),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildNoteField({
    required Color surfaceColor,
    required Color borderColor,
    required Color textColor,
    required Color mutedColor,
    required Color primaryColor,
  }) {
    return TextFormField(
      controller: _noteController,
      maxLines: 3,
      style: TextStyle(
        fontSize: 15,
        color: textColor,
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        labelText: 'Note (optional)',
        labelStyle: TextStyle(
          fontSize: 14,
          color: mutedColor,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 14,
          color: primaryColor,
          fontWeight: FontWeight.w600,
        ),
        hintText: 'Add note...',
        hintStyle: TextStyle(color: mutedColor, fontSize: 15),
        filled: true,
        fillColor: surfaceColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
    );
  }

  Widget _buildSaveButton({
    required bool isDark,
    required Color primaryColor,
    required Color onPrimaryColor,
  }) {
    // An edit cannot be saved before its row arrives: the values on screen would be the
    // form's defaults rather than the transaction's. Disabled, rather than accepting a tap
    // that quietly does nothing.
    final bool canSave = widget.transactionId == null || _createdAt != null;

    final Color disabledBg = isDark
        ? const Color(0xFF244239).withOpacity(0.5)
        : const Color(0xFFE5E7EB);
    final Color disabledFg = isDark
        ? const Color(0xFFA8BDB3).withOpacity(0.5)
        : const Color(0xFF9CA3AF);

    return FilledButton.icon(
      onPressed: (_isLoading || !canSave) ? null : _saveTransaction,
      icon: _isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(onPrimaryColor),
              ),
            )
          : const Icon(Icons.save_rounded, size: 20),
      label: Text(widget.transactionId == null ? 'Save' : 'Update'),
      style: FilledButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: onPrimaryColor,
        disabledBackgroundColor: disabledBg,
        disabledForegroundColor: disabledFg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate() || _selectedCategoryId == null) return;

    // The disabled button above is what keeps an edit from getting here without its row;
    // this is the backstop for a future path that forgets to ask.
    assert(widget.transactionId == null || _createdAt != null,
        'the edit path must load the row before it can save');

    setState(() => _isLoading = true);

    try {
      final transaction = TransactionEntity(
        id: widget.transactionId ?? 0,
        type: _type,
        // The validator above has already rejected anything that does not
        // parse, and anything that is not above zero.
        amount: parseIdrAmount(_amountController.text)!,
        categoryId: _selectedCategoryId!,
        subcategoryId: _selectedSubcategoryId,
        note: _noteController.text.isEmpty ? null : _noteController.text,
        date: _dateOnly(_date),
        createdAt: _createdAt ?? DateTime.now(),
      );

      if (widget.transactionId == null) {
        await ref.read(addTransactionUseCaseProvider).call(transaction);
      } else {
        await ref.read(updateTransactionUseCaseProvider).call(transaction);
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: TextStyle(
                color: isDark ? const Color(0xFF101916) : Colors.white,
              ),
            ),
            backgroundColor: isDark
                ? const Color(0xFFFF9393)
                : Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

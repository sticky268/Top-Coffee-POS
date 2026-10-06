import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../application/expense_categories_controller.dart';
import '../application/expense_categories_state.dart';
import '../data/expenses_repository.dart';
import '../domain/expense_models.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, this.expense});

  final Expense? expense;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  int? _selectedCategoryId;
  DateTime _spentAt = DateTime.now();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense != null) {
      _selectedCategoryId = expense.expenseCategoryId;
      _amountController.text = expense.amount.toStringAsFixed(2);
      _descriptionController.text = expense.description ?? '';
      _spentAt = expense.spentAt.toLocal();
    }

    Future.microtask(
      () => ref.read(expenseCategoriesControllerProvider.notifier).load(),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveExpense() async {
    final categoryId = _selectedCategoryId;
    final amount = double.tryParse(_amountController.text.trim());

    if (categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an expense category.')),
      );
      return;
    }

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final repository = ref.read(expensesRepositoryProvider);
      final description = _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim();
      final spentAt = DateFormat('yyyy-MM-dd').format(_spentAt);

      if (widget.expense == null) {
        await repository.createExpense(
          categoryId: categoryId,
          amount: amount,
          description: description,
          spentAt: spentAt,
        );
      } else {
        await repository.updateExpense(
          id: widget.expense!.id,
          categoryId: categoryId,
          amount: amount,
          description: description,
          spentAt: spentAt,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.expense == null
                ? 'Expense created successfully.'
                : 'Expense updated successfully.',
          ),
        ),
      );

      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not save expense.')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _selectCategory(List<ExpenseCategory> categories) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Select Category'),
          children: categories
              .map(
                (category) => SimpleDialogOption(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(category.id);
                  },
                  child: Text(category.name),
                ),
              )
              .toList(),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedCategoryId = selected;
      });
    }
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _spentAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (selected != null) {
      setState(() {
        _spentAt = selected;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryState = ref.watch(expenseCategoriesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.expense == null ? 'Add Expense' : 'Edit Expense'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            switch (categoryState) {
              ExpenseCategoriesLoading() => const LinearProgressIndicator(),
              ExpenseCategoriesError(:final message) => Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              ExpenseCategoriesLoaded(:final categories) =>
                pos_ui.ActionSurface(
                  onTap: () => _selectCategory(categories),
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      _selectedCategoryId == null
                          ? 'Select category'
                          : categories
                                .firstWhere(
                                  (category) =>
                                      category.id == _selectedCategoryId,
                                )
                                .name,
                    ),
                  ),
                ),
            },
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLength: 255,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What was this expense for?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            pos_ui.ActionSurface(
              onTap: _selectDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Spent date',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined),
                    const SizedBox(width: 16),
                    Text(DateFormat('MMM d, yyyy').format(_spentAt)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            pos_ui.PrimaryButton.icon(
              onPressed: _isSaving ? null : _saveExpense,
              isLoading: _isSaving,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                _isSaving
                    ? 'Saving...'
                    : (widget.expense == null
                          ? 'Save Expense'
                          : 'Update Expense'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

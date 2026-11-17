import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';

class _CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final int? parsed = int.tryParse(digitsOnly);
    if (parsed == null) return oldValue;

    final double value = parsed / 100.0;
    final List<String> parts = value.toStringAsFixed(2).split('.');
    final String whole = parts[0].padLeft(2, '0');
    final String formatted = '$whole.${parts[1]}';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class BudgetManagementScreen extends StatefulWidget {
  final User user;
  final int? initialMonth;
  final int? initialYear;

  const BudgetManagementScreen({
    super.key,
    required this.user,
    this.initialMonth,
    this.initialYear,
  });

  @override
  State<BudgetManagementScreen> createState() => _BudgetManagementScreenState();
}

class _BudgetManagementScreenState extends State<BudgetManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  late int _selectedMonth;
  late int _selectedYear;

  final List<String> _expenseCategories = [
    'Supermarket',
    'Clothing',
    'Entertainment',
    'Transport',
    'Education',
    'Travel',
    'Food',
    'House',
    'Other'
  ];

  final List<String> _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
  ];

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.initialMonth ?? DateTime.now().month;
    _selectedYear = widget.initialYear ?? DateTime.now().year;
    _notificationService.init();
  }

  String _getDisplayCurrency(String? currencyCode, String fallbackSymbol) {
    if (currencyCode == null || currencyCode.isEmpty) {
      return fallbackSymbol;
    }
    switch (currencyCode.toUpperCase()) {
      case 'MYR':
        return 'RM';
      case 'SGD':
        return 'S\$';
      case 'JPY':
      case 'CNY':
        return '¥';
      case 'HKD':
        return 'HK\$';
      case 'KRW':
        return '₩';
      case 'THB':
        return '฿';
      case 'IDR':
        return 'Rp';
      case 'VND':
        return '₫';
      case 'PHP':
        return '₱';
      case 'TWD':
        return 'NT\$';
      case 'INR':
        return '₹';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'AUD':
        return 'A\$';
      case 'CAD':
        return 'C\$';
      case 'NZD':
        return 'NZ\$';
      default:
        return currencyCode;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'supermarket':
        return Icons.shopping_cart;
      case 'clothing':
        return Icons.checkroom;
      case 'entertainment':
        return Icons.ondemand_video;
      case 'transport':
        return Icons.directions_bus;
      case 'education':
        return Icons.school;
      case 'travel':
        return Icons.flight;
      case 'food':
        return Icons.fastfood;
      case 'house':
        return Icons.home;
      default:
        return Icons.grid_view_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'supermarket':
        return Colors.redAccent;
      case 'clothing':
        return Colors.lightBlueAccent;
      case 'entertainment':
        return Colors.purpleAccent;
      case 'transport':
        return Colors.cyanAccent;
      case 'education':
        return Colors.tealAccent;
      case 'travel':
        return Colors.pinkAccent;
      case 'food':
        return Colors.orangeAccent;
      case 'house':
        return Colors.white70;
      default:
        return Colors.white70;
    }
  }

  String _formatInitialCurrency(double amount) {
    if (amount <= 0.0) return '';
    final List<String> parts = amount.toStringAsFixed(2).split('.');
    return '${parts[0].padLeft(2, '0')}.${parts[1]}';
  }

  void _showSetBudgetDialog(
      String category,
      double currentAmount,
      String currencySymbol,
      ) {
    final controller = TextEditingController(
      text: _formatInitialCurrency(currentAmount),
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF132247),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Set Budget for $category',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            _CurrencyInputFormatter(),
          ],
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Budget Amount',
            labelStyle: const TextStyle(color: Colors.white54),
            hintText: '00.00',
            hintStyle: const TextStyle(color: Colors.white24),
            prefixText: '$currencySymbol ',
            prefixStyle: const TextStyle(color: Colors.white),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2F80ED)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2F80ED),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final double newAmount = double.tryParse(controller.text) ?? 0.0;
              final navigator = Navigator.of(dialogContext);
              await _firestoreService.setCategoryBudget(
                widget.user.uid,
                _selectedYear,
                _selectedMonth,
                category,
                newAmount,
              );
              navigator.pop();
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showTransferModal(
      Map<String, double> budgets,
      String currencySymbol,
      ) {
    if (_expenseCategories.isEmpty) return;
    String fromCategory = _expenseCategories.first;
    String toCategory =
    _expenseCategories.length > 1 ? _expenseCategories[1] : _expenseCategories.first;
    final amountController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF132247),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (builderContext, setModalState) {
            final double fromAllocated = budgets[fromCategory] ?? 0.0;
            final double toAllocated = budgets[toCategory] ?? 0.0;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(builderContext).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      'Transfer Budget',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('From Category', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2642),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: fromCategory,
                        dropdownColor: const Color(0xFF132247),
                        isExpanded: true,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        items: _expenseCategories.map((cat) {
                          return DropdownMenuItem(value: cat, child: Text(cat));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              fromCategory = val;
                              if (fromCategory == toCategory) {
                                toCategory =
                                    _expenseCategories.firstWhere((c) => c != fromCategory);
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Available: $currencySymbol${fromAllocated.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  const Text('To Category', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2642),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: toCategory,
                        dropdownColor: const Color(0xFF132247),
                        isExpanded: true,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        items: _expenseCategories.where((c) => c != fromCategory).map((cat) {
                          return DropdownMenuItem(value: cat, child: Text(cat));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              toCategory = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current Allocation: $currencySymbol${toAllocated.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      _CurrencyInputFormatter(),
                    ],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Transfer Amount',
                      labelStyle: const TextStyle(color: Colors.white54),
                      hintText: '00.00',
                      hintStyle: const TextStyle(color: Colors.white24),
                      prefixText: '$currencySymbol ',
                      prefixStyle: const TextStyle(color: Colors.white),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2F80ED)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2F80ED),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        final double transferAmt = double.tryParse(amountController.text) ?? 0.0;
                        if (transferAmt <= 0.0) return;

                        if (transferAmt > fromAllocated) {
                          ScaffoldMessenger.of(builderContext).showSnackBar(
                            const SnackBar(
                              content: Text('Transfer amount exceeds available budget!'),
                            ),
                          );
                          return;
                        }

                        final navigator = Navigator.of(builderContext);
                        await _firestoreService.transferBudget(
                          userId: widget.user.uid,
                          year: _selectedYear,
                          month: _selectedMonth,
                          fromCategory: fromCategory,
                          toCategory: toCategory,
                          transferAmount: transferAmt,
                          currentFromAllocated: fromAllocated,
                          currentToAllocated: toAllocated,
                        );

                        navigator.pop();
                      },
                      child: const Text(
                        'Confirm Transfer',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBudgetBody(String currencySymbol) {
    return StreamBuilder<Map<String, double>>(
    stream: _firestoreService.getMonthlyBudgets(
      widget.user.uid,
      _selectedYear,
      _selectedMonth,
    ),
    builder: (context, budgetSnapshot) {
      final Map<String, double> budgets = budgetSnapshot.data ?? <String, double>{};

      return StreamBuilder<List<TransactionModel>>(
        stream: _firestoreService.getTransactions(widget.user.uid),
        builder: (context, txSnapshot) {
          final List<TransactionModel> allTxs = txSnapshot.data ?? <TransactionModel>[];

          final List<TransactionModel> monthFilteredTxs = allTxs
              .where((tx) =>
          tx.type == 'expense' &&
              tx.date.year == _selectedYear &&
              tx.date.month == _selectedMonth)
              .toList();

          final Map<String, double> categorySpent = <String, double>{};
          for (final TransactionModel tx in monthFilteredTxs) {
            final double current = categorySpent[tx.category] ?? 0.0;
            categorySpent[tx.category] = current + tx.amount;
          }

          double totalBudget = 0.0;
          for (final String cat in _expenseCategories) {
            totalBudget += budgets[cat] ?? 0.0;
          }

          double totalSpent = 0.0;
          for (final double s in categorySpent.values) {
            totalSpent += s;
          }

          // Trigger phone notifications when total or category budget hits >= 80% or > 100%
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _notificationService.checkAndNotifyBudgetAlerts(
              year: _selectedYear,
              month: _selectedMonth,
              currencySymbol: currencySymbol,
              totalBudget: totalBudget,
              totalSpent: totalSpent,
              budgets: budgets,
              categorySpent: categorySpent,
            );
          });

          double overallPercentage = totalBudget > 0 ? (totalSpent / totalBudget * 100) : 0;
          final bool isOverallOverBudget = (totalBudget > 0.0) && (totalSpent > totalBudget);
          final bool isOverallNearLimit =
              (totalBudget > 0.0) && !isOverallOverBudget && (overallPercentage >= 80.0);
          final double remainingBudget = (totalBudget - totalSpent).clamp(0.0, double.infinity);

          return Column(
            children: [
              // Total Budget Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2738),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF293548),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total budget',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: totalBudget),
                              duration: const Duration(milliseconds: 400),
                              builder: (context, val, _) => Text(
                                '$currencySymbol${val.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Budget period',
                              style: TextStyle(color: Colors.white38, fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: overallPercentage),
                          duration: const Duration(milliseconds: 400),
                          builder: (context, val, _) => Text(
                            '${val.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: isOverallOverBudget
                                  ? Colors.redAccent
                                  : (isOverallNearLimit ? Colors.amberAccent : Colors.white70),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: totalSpent),
                          duration: const Duration(milliseconds: 400),
                          builder: (context, val, _) => Text(
                            '$currencySymbol${val.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: isOverallOverBudget
                                  ? Colors.redAccent
                                  : (isOverallNearLimit ? Colors.amberAccent : Colors.white),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '01 ${_months[_selectedMonth - 1]} - 30 ${_months[_selectedMonth - 1]}',
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Over-Budget Warning Banner
              if (isOverallOverBudget)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB03A2E).withOpacity(0.2),
                    border: Border.all(color: Colors.redAccent, width: 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Warning: You have exceeded your total budget limit!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _showTransferModal(budgets, currencySymbol),
                        child: const Text(
                          'Transfer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              // Low-Budget Warning Banner (80% - 100% used)
              else if (isOverallNearLimit)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.16),
                    border: Border.all(color: Colors.amberAccent, width: 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active_outlined,
                        color: Colors.amberAccent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Low budget alert: ${overallPercentage.toStringAsFixed(0)}% used ($currencySymbol${remainingBudget.toStringAsFixed(2)} left).',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _showTransferModal(budgets, currencySymbol),
                        child: const Text(
                          'Transfer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Transfer Budget Button
              Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C5CE7), Color(0xFF4834DF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C5CE7).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _showTransferModal(budgets, currencySymbol),
                  icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 20),
                  label: const Text(
                    'Transfer Budget',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Categories List
              Expanded(
                child: ListView.builder(
                  itemCount: _expenseCategories.length,
                  itemBuilder: (context, index) {
                    final String category = _expenseCategories[index];
                    final double allocated = budgets[category] ?? 0.0;
                    final double spent = categorySpent[category] ?? 0.0;

                    double ratio = allocated > 0 ? (spent / allocated).clamp(0.0, 1.0) : 0.0;
                    int percentage = (ratio * 100).toInt();
                    final bool isCategoryOver = (allocated > 0.0) && (spent > allocated);
                    final bool isCategoryLow =
                        (allocated > 0.0) && !isCategoryOver && (ratio >= 0.8);

                    Color barColor = isCategoryOver
                        ? const Color(0xFFB03A2E)
                        : (isCategoryLow
                        ? const Color(0xFF8A5A14)
                        : (index % 2 == 0
                        ? const Color(0xFF294A6B)
                        : const Color(0xFF1E405E)));

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2232),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                    begin: 0,
                                    end: ratio > 0 ? ratio : 0.001,
                                  ),
                                  duration: const Duration(milliseconds: 400),
                                  builder: (context, animatedRatio, _) => FractionallySizedBox(
                                    widthFactor: animatedRatio,
                                    child: Container(color: barColor),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black26,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          _getCategoryIcon(category),
                                          color: _getCategoryColor(category),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                category,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if (isCategoryOver) ...[
                                                const SizedBox(width: 6),
                                                const Icon(
                                                  Icons.warning_rounded,
                                                  color: Colors.redAccent,
                                                  size: 14,
                                                ),
                                              ] else if (isCategoryLow) ...[
                                                const SizedBox(width: 6),
                                                const Icon(
                                                  Icons.error_outline_rounded,
                                                  color: Colors.amberAccent,
                                                  size: 14,
                                                ),
                                              ]
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          TweenAnimationBuilder<double>(
                                            tween: Tween<double>(begin: 0, end: allocated),
                                            duration: const Duration(milliseconds: 400),
                                            builder: (context, val, _) => Text(
                                              '$currencySymbol${val.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '$percentage%',
                                            style: TextStyle(
                                              color: isCategoryOver
                                                  ? Colors.redAccent
                                                  : (isCategoryLow
                                                  ? Colors.amberAccent
                                                  : Colors.white70),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          TweenAnimationBuilder<double>(
                                            tween: Tween<double>(begin: 0, end: spent),
                                            duration: const Duration(milliseconds: 400),
                                            builder: (context, val, _) => Text(
                                              '$currencySymbol${val.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: isCategoryOver
                                                    ? Colors.redAccent
                                                    : (isCategoryLow
                                                    ? Colors.amberAccent
                                                    : Colors.white),
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(
                                          Icons.settings_outlined,
                                          color: Colors.white70,
                                          size: 20,
                                        ),
                                        onPressed: () => _showSetBudgetDialog(
                                          category,
                                          allocated,
                                          currencySymbol,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121824),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: _firestoreService.getUserProfile(widget.user.uid),
          builder: (context, profileSnapshot) {
            String currencySymbol = 'RM';

            final Map<String, dynamic>? profileData =
            profileSnapshot.data?.data() as Map<String, dynamic>?;
            if (profileData != null) {
              final String? savedSymbol = profileData['currencySymbol'] as String?;
              final String? savedCode = profileData['currencyCode'] as String?;
              if (savedSymbol != null && savedSymbol.isNotEmpty) {
                currencySymbol = savedSymbol;
              } else if (savedCode != null) {
                currencySymbol = _getDisplayCurrency(savedCode, 'RM');
              }
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1E2738),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 18),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Myself',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F80ED),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Monthly',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: _buildBudgetBody(currencySymbol),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
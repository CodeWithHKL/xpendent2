import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_flags/country_flags.dart';

import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';

class AddTransactionScreen extends StatefulWidget {
  final String userId;
  final String initialType; // 'income' or 'expense'

  const AddTransactionScreen({
    super.key,
    required this.userId,
    required this.initialType,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  late String _type;
  String _selectedCategory = 'Supermarket';
  String _selectedCurrency = 'MYR';
  bool _hasInitializedCurrency = false;

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isSubmitting = false;

  static const Map<String, String> _currencyToCountryMap = {
    'MYR': 'MY',
    'SGD': 'SG',
    'JPY': 'JP',
    'CNY': 'CN',
    'HKD': 'HK',
    'KRW': 'KR',
    'THB': 'TH',
    'IDR': 'ID',
    'VND': 'VN',
    'PHP': 'PH',
    'TWD': 'TW',
    'INR': 'IN',
    'AED': 'AE',
    'SAR': 'SA',
    'USD': 'US',
    'EUR': 'EU',
    'GBP': 'GB',
    'AUD': 'AU',
    'CAD': 'CA',
    'CHF': 'CH',
    'NZD': 'NZ',
  };

  final List<String> _defaultExpenseCategories = [
    'Supermarket',
    'Clothing',
    'Entertainment',
    'Transport',
    'Education',
    'Travel',
    'Food',
    'House',
    'Other',
  ];

  final List<String> _defaultIncomeCategories = [
    'Allowance/Sponsorship',
    'Family',
    'Part-Time Job',
    'Other Income',
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _selectedCategory = _type == 'income'
        ? _defaultIncomeCategories.first
        : _defaultExpenseCategories.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String category, Map<String, dynamic>? customData) {
    if (customData != null && customData['iconCodePoint'] != null) {
      return IconData(customData['iconCodePoint'], fontFamily: 'MaterialIcons');
    }
    switch (category) {
      case 'Supermarket':
        return Icons.shopping_cart;
      case 'Clothing':
        return Icons.checkroom;
      case 'Entertainment':
        return Icons.ondemand_video;
      case 'Transport':
        return Icons.directions_bus;
      case 'Education':
        return Icons.school;
      case 'Travel':
        return Icons.flight;
      case 'Food':
        return Icons.fastfood;
      case 'House':
        return Icons.home;
      case 'Allowance/Sponsorship':
        return Icons.account_balance_wallet;
      case 'Family':
        return Icons.family_restroom;
      case 'Part-Time Job':
        return Icons.work_outline;
      default:
        return Icons.grid_view_rounded;
    }
  }

  Color _getCategoryColor(String category, Map<String, dynamic>? customData) {
    if (customData != null && customData['colorValue'] != null) {
      return Color(customData['colorValue']);
    }
    switch (category) {
      case 'Supermarket':
        return Colors.redAccent;
      case 'Clothing':
        return Colors.blueAccent;
      case 'Entertainment':
        return Colors.purpleAccent;
      case 'Transport':
        return Colors.lightBlueAccent;
      case 'Education':
        return Colors.tealAccent;
      case 'Travel':
        return Colors.pinkAccent;
      case 'Food':
        return Colors.orangeAccent;
      case 'House':
        return Colors.indigoAccent;
      case 'Allowance/Sponsorship':
        return Colors.blueAccent;
      case 'Family':
        return Colors.pinkAccent;
      case 'Part-Time Job':
        return Colors.greenAccent;
      default:
        return Colors.lightBlueAccent;
    }
  }

  String _getCountryCode(String currencyCode) {
    return _currencyToCountryMap[currencyCode.toUpperCase()] ?? 'MY';
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF1D61E7),
              onPrimary: Colors.white,
              surface: Color(0xFF132247),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF1D61E7),
              onPrimary: Colors.white,
              surface: Color(0xFF132247),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _showCurrencySelectorBottomSheet({
    required List<String> availableCurrencies,
    required String primaryCurrency,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131D33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Currency',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...availableCurrencies.map((code) {
                final isSelected = code == _selectedCurrency;
                final isPrimary = code == primaryCurrency;
                final countryCode = _getCountryCode(code);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2642),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF1D61E7) : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: ListTile(
                    onTap: () {
                      setState(() {
                        _selectedCurrency = code;
                      });
                      Navigator.pop(context);
                    },
                    leading: CountryFlag.fromCountryCode(
                      countryCode,
                      width: 36,
                      height: 24,
                      shape: const RoundedRectangle(4),
                    ),
                    title: Text(
                      code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isPrimary
                        ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Primary',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                        : isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFF1D61E7), size: 20)
                        : null,
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;

    final double amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount (> 0.00)')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final DateTime finalDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final transaction = TransactionModel(
      id: '',
      title: _titleController.text.trim(),
      amount: amount,
      date: finalDateTime,
      category: _selectedCategory,
      type: _type,
      currencyCode: _selectedCurrency,
    );

    try {
      await _firestoreService.addTransaction(widget.userId, transaction);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save transaction: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isIncome = _type == 'income';

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          isIncome ? 'Plan an income' : 'Plan an outcome',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isIncome ? Colors.green : Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isIncome ? Icons.add : Icons.remove,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Category',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestoreService.getCustomCategories(widget.userId),
                  builder: (context, snapshot) {
                    List<String> categoryTitles = List.from(
                      isIncome ? _defaultIncomeCategories : _defaultExpenseCategories,
                    );
                    Map<String, Map<String, dynamic>> customDataMap = {};

                    if (snapshot.hasData && snapshot.data != null) {
                      final currentType = isIncome ? 'income' : 'expense';
                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        if (data['type'] == currentType) {
                          final title = data['title'] as String;
                          customDataMap[title] = data;

                          if (!categoryTitles.contains(title)) {
                            int insertPos = categoryTitles.length > 1
                                ? categoryTitles.length - 1
                                : categoryTitles.length;
                            categoryTitles.insert(insertPos, title);
                          }
                        }
                      }
                    }

                    if (!categoryTitles.contains(_selectedCategory)) {
                      _selectedCategory = categoryTitles.first;
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF142240),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          dropdownColor: const Color(0xFF142240),
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                          items: categoryTitles.map((cat) {
                            final customData = customDataMap[cat];
                            final icon = _getCategoryIcon(cat, customData);
                            final color = _getCategoryColor(cat, customData);

                            return DropdownMenuItem<String>(
                              value: cat,
                              child: Row(
                                children: [
                                  Icon(icon, color: color, size: 20),
                                  const SizedBox(width: 12),
                                  Text(
                                    cat,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedCategory = val);
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                const Text(
                  'Amount',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          CurrencyInputFormatter(),
                        ],
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF142240),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          errorStyle: const TextStyle(color: Colors.redAccent),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Enter an amount';
                          }
                          final numVal = double.tryParse(val.trim());
                          if (numVal == null || numVal <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    StreamBuilder<DocumentSnapshot>(
                      stream: _firestoreService.getUserProfile(widget.userId),
                      builder: (context, snapshot) {
                        String primaryCurrency = 'MYR';
                        List<String> otherCurrencies = [];

                        if (snapshot.hasData && snapshot.data!.data() != null) {
                          final data = snapshot.data!.data() as Map<String, dynamic>;
                          if (data['currencyCode'] != null) {
                            primaryCurrency = data['currencyCode'] as String;
                          }
                          if (data['otherCurrencies'] != null) {
                            otherCurrencies = List<String>.from(data['otherCurrencies'] as List);
                          }
                        }

                        final List<String> userCurrencies = [
                          primaryCurrency,
                          ...otherCurrencies.where((c) => c != primaryCurrency),
                        ];

                        if (!_hasInitializedCurrency && userCurrencies.isNotEmpty) {
                          _selectedCurrency = primaryCurrency;
                          _hasInitializedCurrency = true;
                        }

                        final countryCode = _getCountryCode(_selectedCurrency);

                        return GestureDetector(
                          onTap: () {
                            _showCurrencySelectorBottomSheet(
                              availableCurrencies: userCurrencies,
                              primaryCurrency: primaryCurrency,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF142240),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                CountryFlag.fromCountryCode(
                                  countryCode,
                                  width: 22,
                                  height: 15,
                                  shape: const RoundedRectangle(3),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _selectedCurrency,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Date',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF142240),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                DateFormat('dd MMMM yyyy').format(_selectedDate),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const Icon(
                                Icons.calendar_today_outlined,
                                color: Colors.white54,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF233660),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedDate = DateTime.now();
                          });
                        },
                        child: const Text(
                          'Today',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Time',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF142240),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedTime.format(context),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Icon(
                          Icons.access_time_rounded,
                          color: Colors.white54,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Name',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'e.g. Groceries',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF142240),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D61E7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _saveTransaction,
                    child: _isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      'Create',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    double value = double.parse(newValue.text);
    String formatted = (value / 100).toStringAsFixed(2);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
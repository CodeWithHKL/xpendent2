import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_flags/country_flags.dart';
import '../../services/firestore_service.dart';

class CurrencyModel {
  final String code;        // e.g., 'MYR'
  final String countryCode; // e.g., 'MY'
  final String name;
  final String symbol;
  final double rateToUsd;

  const CurrencyModel({
    required this.code,
    required this.countryCode,
    required this.name,
    required this.symbol,
    required this.rateToUsd,
  });
}

class CurrencyScreen extends StatefulWidget {
  final User user;

  const CurrencyScreen({super.key, required this.user});

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isSaving = false;
  bool _hasChangedCurrency = false;

  // Master Currency Catalog (Asian Currencies First)
  static const List<CurrencyModel> _allCurrencies = [
    // --- Southeast & East Asia ---
    CurrencyModel(code: 'MYR', countryCode: 'MY', name: 'Malaysian Ringgit', symbol: 'RM', rateToUsd: 4.45),
    CurrencyModel(code: 'SGD', countryCode: 'SG', name: 'Singapore Dollar', symbol: 'S\$', rateToUsd: 1.34),
    CurrencyModel(code: 'JPY', countryCode: 'JP', name: 'Japanese Yen', symbol: '¥', rateToUsd: 154.20),
    CurrencyModel(code: 'CNY', countryCode: 'CN', name: 'Chinese Yuan', symbol: '¥', rateToUsd: 7.23),
    CurrencyModel(code: 'HKD', countryCode: 'HK', name: 'Hong Kong Dollar', symbol: 'HK\$', rateToUsd: 7.82),
    CurrencyModel(code: 'KRW', countryCode: 'KR', name: 'South Korean Won', symbol: '₩', rateToUsd: 1380.00),
    CurrencyModel(code: 'THB', countryCode: 'TH', name: 'Thai Baht', symbol: '฿', rateToUsd: 36.80),
    CurrencyModel(code: 'IDR', countryCode: 'ID', name: 'Indonesian Rupiah', symbol: 'Rp', rateToUsd: 16250.00),
    CurrencyModel(code: 'VND', countryCode: 'VN', name: 'Vietnamese Dong', symbol: '₫', rateToUsd: 25450.00),
    CurrencyModel(code: 'PHP', countryCode: 'PH', name: 'Philippine Peso', symbol: '₱', rateToUsd: 58.20),
    CurrencyModel(code: 'TWD', countryCode: 'TW', name: 'New Taiwan Dollar', symbol: 'NT\$', rateToUsd: 32.40),

    // --- South & West Asia ---
    CurrencyModel(code: 'INR', countryCode: 'IN', name: 'Indian Rupee', symbol: '₹', rateToUsd: 83.50),
    CurrencyModel(code: 'AED', countryCode: 'AE', name: 'UAE Dirham', symbol: 'AED', rateToUsd: 3.67),
    CurrencyModel(code: 'SAR', countryCode: 'SA', name: 'Saudi Riyal', symbol: 'SAR', rateToUsd: 3.75),

    // --- Global Majors ---
    CurrencyModel(code: 'USD', countryCode: 'US', name: 'US Dollar', symbol: '\$', rateToUsd: 1.00),
    CurrencyModel(code: 'EUR', countryCode: 'EU', name: 'Euro', symbol: '€', rateToUsd: 0.92),
    CurrencyModel(code: 'GBP', countryCode: 'GB', name: 'British Pound', symbol: '£', rateToUsd: 0.79),
    CurrencyModel(code: 'AUD', countryCode: 'AU', name: 'Australian Dollar', symbol: 'A\$', rateToUsd: 1.51),
    CurrencyModel(code: 'CAD', countryCode: 'CA', name: 'Canadian Dollar', symbol: 'C\$', rateToUsd: 1.36),
    CurrencyModel(code: 'CHF', countryCode: 'CH', name: 'Swiss Franc', symbol: 'CHF', rateToUsd: 0.91),
    CurrencyModel(code: 'NZD', countryCode: 'NZ', name: 'New Zealand Dollar', symbol: 'NZ\$', rateToUsd: 1.65),
  ];

  static CurrencyModel getCurrencyByCode(String code) {
    return _allCurrencies.firstWhere(
          (c) => c.code == code,
      orElse: () => _allCurrencies.first,
    );
  }

  String _calculateRelativeRate(CurrencyModel base, CurrencyModel secondary) {
    double converted = secondary.rateToUsd / base.rateToUsd;
    if (converted >= 100) {
      return '1 ${base.code} = ${converted.toStringAsFixed(0)} ${secondary.code}';
    } else if (converted >= 1) {
      return '1 ${base.code} = ${converted.toStringAsFixed(2)} ${secondary.code}';
    } else {
      return '1 ${base.code} = ${converted.toStringAsFixed(4)} ${secondary.code}';
    }
  }

  Future<void> _updateMainCurrency(CurrencyModel currency) async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set({
        'currencyCode': currency.code,
        'currencySymbol': currency.symbol,
      }, SetOptions(merge: true));

      _hasChangedCurrency = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Main currency set to ${currency.code} (${currency.symbol})'),
            backgroundColor: const Color(0xFF1D61E7),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update main currency: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addOtherCurrency(CurrencyModel currency, List<String> currentOthers) async {
    if (currentOthers.contains(currency.code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${currency.code} is already in your list')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      List<String> updated = [...currentOthers, currency.code];
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set({'otherCurrencies': updated}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add currency: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeOtherCurrency(String code, List<String> currentOthers) async {
    setState(() => _isSaving = true);
    try {
      List<String> updated = currentOthers.where((c) => c != code).toList();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set({'otherCurrencies': updated}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove currency: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Renders rectangular flag directly using CountryFlag shape
  Widget _buildFlagAvatar(String countryCode, {double width = 42, double height = 28}) {
    return CountryFlag.fromCountryCode(
      countryCode.toUpperCase(),
      width: width,
      height: height,
      shape: const RoundedRectangle(6),
    );
  }

  void _showCurrencyPickerBottomSheet({
    required String title,
    required String currentSelectedCode,
    required Function(CurrencyModel selected) onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131D33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _allCurrencies.where((c) {
              final q = searchQuery.toLowerCase();
              return c.name.toLowerCase().contains(q) ||
                  c.code.toLowerCase().contains(q) ||
                  c.symbol.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
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
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    onChanged: (val) => setModalState(() => searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search country or currency...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E2D4A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final currency = filtered[index];
                        final isSelected = currency.code == currentSelectedCode;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
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
                              Navigator.pop(context);
                              onSelect(currency);
                            },
                            leading: _buildFlagAvatar(currency.countryCode, width: 38, height: 26),
                            title: Text(
                              currency.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '${currency.code} (${currency.symbol})',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle, color: Color(0xFF1D61E7), size: 20)
                                : const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
                          ),
                        );
                      },
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          Navigator.pop(context, _hasChangedCurrency);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1626),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1626),
          elevation: 0,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF1A2642),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
            onPressed: () => Navigator.pop(context, _hasChangedCurrency),
          ),
          title: const Text(
            'Currency rates',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: _firestoreService.getUserProfile(widget.user.uid),
          builder: (context, snapshot) {
            String mainCode = 'MYR';
            List<String> otherCodes = [];

            if (snapshot.hasData && snapshot.data!.data() != null) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              if (data['currencyCode'] != null) {
                mainCode = data['currencyCode'] as String;
              }
              if (data['otherCurrencies'] != null) {
                otherCodes = List<String>.from(data['otherCurrencies'] as List);
              }
            }

            final mainCurrency = getCurrencyByCode(mainCode);

            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- SECTION 1: MAIN CURRENCY ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Main Currency',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFF1E2D4A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            ),
                            onPressed: () {
                              _showCurrencyPickerBottomSheet(
                                title: 'Select Main Currency',
                                currentSelectedCode: mainCode,
                                onSelect: (selected) => _updateMainCurrency(selected),
                              );
                            },
                            child: const Text(
                              'Change',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Main Currency Display Card
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF382A72), Color(0xFF261D52)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.purpleAccent.withOpacity(0.3), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _buildFlagAvatar(mainCurrency.countryCode, width: 44, height: 30),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mainCurrency.code,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${mainCurrency.name} (${mainCurrency.symbol})',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Primary',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                      const Divider(color: Colors.white12, thickness: 1),
                      const SizedBox(height: 16),

                      // --- SECTION 2: OTHERS ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Others',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFF1E2D4A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            ),
                            onPressed: () {
                              _showCurrencyPickerBottomSheet(
                                title: 'Add Secondary Currency',
                                currentSelectedCode: '',
                                onSelect: (selected) => _addOtherCurrency(selected, otherCodes),
                              );
                            },
                            icon: const Icon(Icons.add, color: Colors.white, size: 16),
                            label: const Text(
                              'Other currency',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Others List View
                      Expanded(
                        child: otherCodes.isEmpty
                            ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.currency_exchange, color: Colors.white24, size: 48),
                              SizedBox(height: 12),
                              Text(
                                'No secondary currencies added yet',
                                style: TextStyle(color: Colors.white38, fontSize: 14),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Tap "Other currency" to track live exchange rates',
                                style: TextStyle(color: Colors.white24, fontSize: 12),
                              ),
                            ],
                          ),
                        )
                            : ListView.builder(
                          itemCount: otherCodes.length,
                          itemBuilder: (context, index) {
                            final code = otherCodes[index];
                            final secondary = getCurrencyByCode(code);
                            final rateText = _calculateRelativeRate(mainCurrency, secondary);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A2642),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                              ),
                              child: Row(
                                children: [
                                  _buildFlagAvatar(secondary.countryCode, width: 40, height: 28),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${secondary.code} (${secondary.symbol})',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          rateText,
                                          style: const TextStyle(
                                            color: Colors.cyanAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    onPressed: () => _removeOtherCurrency(code, otherCodes),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isSaving)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
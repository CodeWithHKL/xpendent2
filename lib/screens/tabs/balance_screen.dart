import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../transactions/transaction_detail_screen.dart';

class BalanceScreen extends StatelessWidget {
  final User user;
  final FirestoreService _firestoreService = FirestoreService();

  BalanceScreen({super.key, required this.user});

  IconData _getCategoryIcon(String category, Map<String, dynamic>? customData) {
    if (customData != null && customData['iconCodePoint'] != null) {
      return IconData(customData['iconCodePoint'], fontFamily: 'MaterialIcons');
    }
    switch (category) {
      case 'Supermarket':
        return Icons.shopping_cart;
      case 'Clothing':
      case 'Shopping':
        return Icons.shopping_bag;
      case 'Entertainment':
        return Icons.movie;
      case 'Transport':
      case 'Transportation':
        return Icons.directions_bus;
      case 'Education':
        return Icons.school;
      case 'Travel':
        return Icons.flight;
      case 'Food':
      case 'Food & Drink':
        return Icons.restaurant;
      case 'House':
        return Icons.home;
      case 'Allowance/Sponsorship':
      case 'Monthly Allowance':
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
      case 'Shopping':
        return Colors.redAccent;
      case 'Clothing':
        return Colors.blueAccent;
      case 'Entertainment':
        return Colors.purpleAccent;
      case 'Transport':
      case 'Transportation':
        return Colors.lightBlueAccent;
      case 'Education':
        return Colors.tealAccent;
      case 'Travel':
        return Colors.pinkAccent;
      case 'Food':
      case 'Food & Drink':
        return Colors.orangeAccent;
      case 'House':
        return Colors.indigoAccent;
      case 'Allowance/Sponsorship':
      case 'Monthly Allowance':
        return Colors.greenAccent;
      case 'Family':
        return Colors.pinkAccent;
      case 'Part-Time Job':
        return Colors.greenAccent;
      default:
        return Colors.lightBlueAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestoreService.getUserProfile(user.uid),
      builder: (context, profileSnapshot) {
        String currencyCode = 'MYR';

        if (profileSnapshot.hasData && profileSnapshot.data!.data() != null) {
          final profileData = profileSnapshot.data!.data() as Map<String, dynamic>;
          if (profileData['currencyCode'] != null &&
              (profileData['currencyCode'] as String).isNotEmpty) {
            currencyCode = profileData['currencyCode'] as String;
          } else if (profileData['currencySymbol'] != null &&
              (profileData['currencySymbol'] as String).isNotEmpty) {
            currencyCode = profileData['currencySymbol'] as String;
          }
        }

        return StreamBuilder<List<TransactionModel>>(
          stream: _firestoreService.getTransactions(user.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
              );
            }

            final transactions = snapshot.data ?? [];

            double totalIncome = 0.0;
            double totalExpense = 0.0;

            for (var tx in transactions) {
              if (tx.type == 'income') {
                totalIncome += tx.amount;
              } else {
                totalExpense += tx.amount;
              }
            }

            double netBalance = totalIncome - totalExpense;

            return StreamBuilder<QuerySnapshot>(
              stream: _firestoreService.getCustomCategories(user.uid),
              builder: (context, customSnapshot) {
                Map<String, Map<String, dynamic>> customDataMap = {};
                if (customSnapshot.hasData && customSnapshot.data != null) {
                  for (var doc in customSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final title = data['title'] as String?;
                    if (title != null) {
                      customDataMap[title] = data;
                    }
                  }
                }

                return Scaffold(
                  backgroundColor: const Color(0xFF0F1626),
                  body: SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- TOP HEADER & BALANCE BANNER ---
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Image.asset(
                                  'assets/wallpaper10.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Color(0xFF1E2D4A), Color(0xFF0F1626)],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.black.withOpacity(0.4),
                                      const Color(0xFF0F1626).withOpacity(0.85),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Title Row
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.account_balance_wallet_outlined,
                                              color: Colors.white, size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          'My Balance',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Balance Card
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF18243E).withOpacity(0.92),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.25),
                                            blurRadius: 15,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Total Balance',
                                            style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${netBalance >= 0 ? '' : '-'}$currencyCode ${netBalance.abs().toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 32,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(vertical: 14),
                                            child: Divider(color: Colors.white12, height: 1),
                                          ),
                                          Row(
                                            children: [
                                              // Income
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(6),
                                                      decoration: BoxDecoration(
                                                        color: Colors.greenAccent.withOpacity(0.15),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: const Icon(Icons.arrow_downward_rounded,
                                                          color: Colors.greenAccent, size: 14),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text('Income',
                                                            style: TextStyle(
                                                                color: Colors.white54, fontSize: 11)),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          '$currencyCode ${totalIncome.toStringAsFixed(2)}',
                                                          style: const TextStyle(
                                                            color: Colors.greenAccent,
                                                            fontSize: 13.5,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                height: 30,
                                                width: 1,
                                                color: Colors.white12,
                                              ),
                                              const SizedBox(width: 16),
                                              // Expense
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(6),
                                                      decoration: BoxDecoration(
                                                        color: Colors.redAccent.withOpacity(0.15),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: const Icon(Icons.arrow_upward_rounded,
                                                          color: Colors.redAccent, size: 14),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text('Expense',
                                                            style: TextStyle(
                                                                color: Colors.white54, fontSize: 11)),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          '$currencyCode ${totalExpense.toStringAsFixed(2)}',
                                                          style: const TextStyle(
                                                            color: Colors.redAccent,
                                                            fontSize: 13.5,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
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
                            ],
                          ),
                        ),

                        // --- TRANSACTION LIST SECTION ---
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Recent Transactions',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${transactions.length} items',
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: transactions.isEmpty
                                      ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.receipt_long_outlined,
                                            size: 48, color: Colors.white.withOpacity(0.2)),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'No transactions yet',
                                          style: TextStyle(color: Colors.white38, fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  )
                                      : ListView.builder(
                                    itemCount: transactions.length,
                                    padding: const EdgeInsets.only(bottom: 30),
                                    itemBuilder: (context, index) {
                                      final tx = transactions[index];
                                      final bool isIncome = tx.type == 'income';
                                      final customData = customDataMap[tx.category];
                                      final categoryIcon = _getCategoryIcon(tx.category, customData);
                                      final categoryColor = _getCategoryColor(tx.category, customData);
                                      final itemCurrency = tx.currencyCode ?? currencyCode;

                                      return GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => TransactionDetailScreen(
                                                userId: user.uid,
                                                transaction: tx,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF18243E),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                                          ),
                                          child: Row(
                                            children: [
                                              // Category Icon
                                              Container(
                                                padding: const EdgeInsets.all(11),
                                                decoration: BoxDecoration(
                                                  color: categoryColor.withOpacity(0.18),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Icon(
                                                  categoryIcon,
                                                  color: categoryColor,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 14),

                                              // Title & Category Name
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      tx.title,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 14.5,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      tx.category,
                                                      style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 12,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),

                                              // Amount & Date
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    '${isIncome ? '+' : '-'}$itemCurrency ${tx.amount.toStringAsFixed(2)}',
                                                    style: TextStyle(
                                                      color: isIncome
                                                          ? Colors.greenAccent
                                                          : Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14.5,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    DateFormat('MMM d, yyyy').format(tx.date),
                                                    style: const TextStyle(
                                                      color: Colors.white38,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
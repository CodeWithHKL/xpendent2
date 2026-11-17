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
              return const Center(child: CircularProgressIndicator());
            }

            final transactions = snapshot.data ?? [];

            // Compute overall balance, income, and expenses
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
                        // --- HOMESCREEN WALLPAPER TOP HEADER CONTAINER ---
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
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
                                          colors: [Color(0xFF132247), Color(0xFF0C1327)],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.only(top: 10, left: 16, right: 16, bottom: 16),
                                color: Colors.black.withOpacity(0.20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Top Title
                                    const Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: Colors.white10,
                                          child: Icon(Icons.person_outline, color: Colors.white, size: 20),
                                        ),
                                        SizedBox(width: 12),
                                        Text(
                                          'My Budget',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),

                                    // Current Balance Box
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E2D4A).withOpacity(0.85),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Current Balance',
                                            style: TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${netBalance >= 0 ? '' : '-'}$currencyCode${netBalance.abs().toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 30,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              // Income summary indicator
                                              Row(
                                                children: [
                                                  const Icon(Icons.north_east, color: Colors.greenAccent, size: 14),
                                                  const SizedBox(width: 4),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Text('Income',
                                                          style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                                                      Text(
                                                        '$currencyCode${totalIncome.toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.bold),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(width: 32),

                                              // Expense summary indicator
                                              Row(
                                                children: [
                                                  const Icon(Icons.south_east, color: Colors.redAccent, size: 14),
                                                  const SizedBox(width: 4),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Text('Expense',
                                                          style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                                                      Text(
                                                        '$currencyCode${totalExpense.toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.bold),
                                                      ),
                                                    ],
                                                  ),
                                                ],
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

                        // --- SCROLLABLE TRANSACTION LIST ---
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 16),
                                const Text(
                                  'Recent Transactions',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: transactions.isEmpty
                                      ? const Center(
                                    child: Text(
                                      'No transactions yet',
                                      style: TextStyle(color: Colors.white38, fontSize: 14),
                                    ),
                                  )
                                      : ListView.builder(
                                    itemCount: transactions.length,
                                    padding: const EdgeInsets.only(bottom: 24),
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
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF142240),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: Colors.white10),
                                          ),
                                          child: Row(
                                            children: [
                                              // Category Icon Container
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: categoryColor.withOpacity(0.2),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  categoryIcon,
                                                  color: categoryColor,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),

                                              // Category & Description
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      tx.category,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      tx.title,
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

                                              // Amount & Date
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    '$itemCurrency${tx.amount.toStringAsFixed(2)}',
                                                    style: TextStyle(
                                                      color: isIncome
                                                          ? Colors.greenAccent
                                                          : Colors.redAccent,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    DateFormat('d/M/yyyy').format(tx.date),
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
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';

class TransactionDetailScreen extends StatelessWidget {
  final String userId;
  final TransactionModel transaction;

  const TransactionDetailScreen({
    super.key,
    required this.userId,
    required this.transaction,
  });

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

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF132247),
        title: const Text('Delete Transaction', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to delete this transaction?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await FirestoreService().deleteTransaction(userId, transaction.id);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String dayHeader = DateFormat('dd MMM').format(transaction.date);
    String weekDay = DateFormat('EEEE').format(transaction.date);
    String fullDateTime = DateFormat('dd MMMM yyyy  hh:mm a').format(transaction.date);

    return Scaffold(
      backgroundColor: const Color(0xFF132247),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E2D50), Color(0xFF0F1626)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirestoreService().getUserProfile(userId),
              builder: (context, profileSnapshot) {
                String defaultCurrency = 'MYR';
                if (profileSnapshot.hasData && profileSnapshot.data!.data() != null) {
                  final data = profileSnapshot.data!.data() as Map<String, dynamic>;
                  if (data['currencyCode'] != null) {
                    defaultCurrency = data['currencyCode'] as String;
                  }
                }

                final displayCurrency = transaction.currencyCode ?? defaultCurrency;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '$dayHeader  ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          weekDay,
                          style: const TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    StreamBuilder<QuerySnapshot>(
                      stream: FirestoreService().getCustomCategories(userId),
                      builder: (context, snapshot) {
                        Map<String, dynamic>? customCategoryData;

                        if (snapshot.hasData && snapshot.data != null) {
                          for (var doc in snapshot.data!.docs) {
                            final data = doc.data() as Map<String, dynamic>;
                            if (data['title'] == transaction.category) {
                              customCategoryData = data;
                              break;
                            }
                          }
                        }

                        final categoryIcon = _getCategoryIcon(transaction.category, customCategoryData);
                        final categoryColor = _getCategoryColor(transaction.category, customCategoryData);

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                categoryIcon,
                                color: categoryColor,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                transaction.category,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    Text(
                      transaction.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),

                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, color: Colors.white, size: 14),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              Text(
                                '$displayCurrency ${transaction.amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Date', style: TextStyle(color: Colors.white54, fontSize: 14)),
                        Text(
                          fullDateTime,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    IconButton(
                      onPressed: () => _confirmDelete(context),
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 28),
                    ),

                    const Spacer(),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';

class CategoryItem {
  final String id;
  final String title;
  final IconData icon;
  final Color iconColor;
  final bool isCustom;

  CategoryItem({
    this.id = '',
    required this.title,
    required this.icon,
    required this.iconColor,
    this.isCustom = false,
  });
}

class CategoriesScreen extends StatefulWidget {
  final User user;
  const CategoriesScreen({super.key, required this.user});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isExpensesSelected = true;

  final List<IconData> _availableIcons = [
    Icons.shopping_cart,
    Icons.fastfood,
    Icons.restaurant,
    Icons.directions_bus,
    Icons.directions_car,
    Icons.flight,
    Icons.school,
    Icons.home,
    Icons.ondemand_video,
    Icons.movie,
    Icons.fitness_center,
    Icons.medical_services,
    Icons.local_hospital,
    Icons.account_balance_wallet,
    Icons.pets,
    Icons.child_care,
    Icons.card_giftcard,
    Icons.phone_iphone,
    Icons.laptop,
    Icons.build,
    Icons.brush,
    Icons.work,
    Icons.savings,
    Icons.star,
  ];

  final List<Color> _availableColors = [
    Colors.redAccent,
    Colors.pinkAccent,
    Colors.purpleAccent,
    Colors.deepPurpleAccent,
    Colors.indigoAccent,
    Colors.blueAccent,
    Colors.lightBlueAccent,
    Colors.cyanAccent,
    Colors.tealAccent,
    Colors.greenAccent,
    Colors.amberAccent,
    Colors.orangeAccent,
  ];

  final List<CategoryItem> _defaultExpenseCategories = [
    CategoryItem(title: 'Supermarket', icon: Icons.shopping_cart, iconColor: Colors.redAccent),
    CategoryItem(title: 'Clothing', icon: Icons.checkroom, iconColor: Colors.lightBlueAccent),
    CategoryItem(title: 'Entertainment', icon: Icons.ondemand_video, iconColor: Colors.purpleAccent),
    CategoryItem(title: 'Transport', icon: Icons.directions_bus, iconColor: Colors.cyanAccent),
    CategoryItem(title: 'Education', icon: Icons.school, iconColor: Colors.tealAccent),
    CategoryItem(title: 'Travel', icon: Icons.flight, iconColor: Colors.pinkAccent),
    CategoryItem(title: 'Food', icon: Icons.fastfood, iconColor: Colors.orangeAccent),
    CategoryItem(title: 'House', icon: Icons.home, iconColor: Colors.white70),
    CategoryItem(title: 'Other', icon: Icons.grid_view_rounded, iconColor: Colors.white70),
  ];

  final List<CategoryItem> _defaultIncomeCategories = [
    CategoryItem(title: 'Allowance/Sponsorship', icon: Icons.account_balance_wallet, iconColor: Colors.blueAccent),
    CategoryItem(title: 'Family', icon: Icons.family_restroom, iconColor: Colors.pinkAccent),
    CategoryItem(title: 'Part-Time Job', icon: Icons.work_outline, iconColor: Colors.greenAccent),
    CategoryItem(title: 'Other Income', icon: Icons.grid_view_rounded, iconColor: Colors.white70),
  ];

  void _confirmDeleteCustomCategory(CategoryItem category) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF132247),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Delete Category',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to delete "${category.title}"?',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                Navigator.pop(context);
                await _firestoreService.deleteCustomCategory(widget.user.uid, category.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Category "${category.title}" deleted')),
                  );
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showAddCategoryDialog() {
    final titleController = TextEditingController();
    IconData selectedIcon = _availableIcons.first;
    Color selectedColor = _availableColors.first;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF132247),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Add New ${_isExpensesSelected ? "Expense" : "Income"} Category',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Category Name',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1E2D4A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Select Icon:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 120,
                      width: double.maxFinite,
                      child: GridView.builder(
                        shrinkWrap: true,
                        itemCount: _availableIcons.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemBuilder: (context, index) {
                          final icon = _availableIcons[index];
                          final isSelected = selectedIcon == icon;
                          return GestureDetector(
                            onTap: () => setDialogState(() => selectedIcon = icon),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: isSelected ? selectedColor.withOpacity(0.3) : const Color(0xFF1E2D4A),
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? selectedColor : Colors.transparent, width: 2),
                              ),
                              child: Icon(icon, color: isSelected ? selectedColor : Colors.white60, size: 18),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Select Color:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 80,
                      width: double.maxFinite,
                      child: GridView.builder(
                        shrinkWrap: true,
                        itemCount: _availableColors.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemBuilder: (context, index) {
                          final color = _availableColors[index];
                          final isSelected = selectedColor == color;
                          return GestureDetector(
                            onTap: () => setDialogState(() => selectedColor = color),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 2.5),
                              ),
                              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
                  onPressed: () async {
                    final text = titleController.text.trim();
                    if (text.isNotEmpty) {
                      Navigator.pop(context);
                      await _firestoreService.addCustomCategory(
                        userId: widget.user.uid,
                        title: text,
                        iconCodePoint: selectedIcon.codePoint,
                        colorValue: selectedColor.value,
                        type: _isExpensesSelected ? 'expense' : 'income',
                      );
                    }
                  },
                  child: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    final String currentType = _isExpensesSelected ? 'expense' : 'income';
    final List<CategoryItem> defaultList = _isExpensesSelected ? _defaultExpenseCategories : _defaultIncomeCategories;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1626),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestoreService.getCustomCategories(widget.user.uid),
          builder: (context, snapshot) {
            List<CategoryItem> customItems = [];

            if (snapshot.hasData) {
              for (var doc in snapshot.data!.docs) {
                final data = doc.data();
                if (data['type'] == currentType) {
                  final int iconCode = data['iconCodePoint'] ?? Icons.label.codePoint;
                  final int colorVal = data['colorValue'] ?? Colors.cyanAccent.value;

                  customItems.add(
                    CategoryItem(
                      id: doc.id,
                      title: data['title'] ?? '',
                      icon: IconData(iconCode, fontFamily: 'MaterialIcons'),
                      iconColor: Color(colorVal),
                      isCustom: true,
                    ),
                  );
                }
              }
            }

            List<CategoryItem> displayList = List.from(defaultList);
            if (displayList.isNotEmpty) {
              displayList.insertAll(displayList.length - 1, customItems);
            } else {
              displayList.addAll(customItems);
            }

            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1A2642),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 20),
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                          const Text(
                            'Categories',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Container(
                        height: 50,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2642),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isExpensesSelected = true),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  decoration: BoxDecoration(
                                    color: _isExpensesSelected ? const Color(0xFFFF4757) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'EXPENSES',
                                      style: TextStyle(
                                        color: _isExpensesSelected ? Colors.white : Colors.white60,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isExpensesSelected = false),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  decoration: BoxDecoration(
                                    color: !_isExpensesSelected ? const Color(0xFF1D61E7) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'INCOME',
                                      style: TextStyle(
                                        color: !_isExpensesSelected ? Colors.white : Colors.white60,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: ListView.builder(
                            key: ValueKey<bool>(_isExpensesSelected),
                            itemCount: displayList.length,
                            itemBuilder: (context, index) {
                              final category = displayList[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A2642),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    Icon(category.icon, color: category.iconColor, size: 20),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        category.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (category.isCustom)
                                      IconButton(
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                        onPressed: () => _confirmDeleteCustomCategory(category),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: FloatingActionButton(
                    backgroundColor: const Color(0xFF6C5CE7),
                    onPressed: _showAddCategoryDialog,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
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
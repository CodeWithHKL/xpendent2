class CategoryBudget {
  final String category;
  final double allocatedAmount;

  CategoryBudget({
    required this.category,
    required this.allocatedAmount,
  });

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'allocatedAmount': allocatedAmount,
    };
  }

  factory CategoryBudget.fromMap(Map<String, dynamic> map) {
    return CategoryBudget(
      category: map['category'] ?? '',
      allocatedAmount: (map['allocatedAmount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
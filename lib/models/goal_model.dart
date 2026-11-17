import 'package:cloud_firestore/cloud_firestore.dart';

class GoalModel {
  final String id;
  final String title;
  final int targetAmount;
  final int currentAmount;
  final DateTime targetDate;

  GoalModel({
    required this.id,
    required this.title,
    required this.targetAmount,
    required this.currentAmount,
    required this.targetDate,
  });

  bool get isCompleted => currentAmount >= targetAmount;

  int get daysRemaining => targetDate.difference(DateTime.now()).inDays;

  factory GoalModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GoalModel(
      id: doc.id,
      title: data['title'] ?? '',
      targetAmount: (data['targetAmount'] as num?)?.toInt() ?? 0,
      currentAmount: (data['currentAmount'] as num?)?.toInt() ?? 0,
      targetDate: (data['targetDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'targetAmount': targetAmount,
      'currentAmount': currentAmount,
      'targetDate': Timestamp.fromDate(targetDate),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
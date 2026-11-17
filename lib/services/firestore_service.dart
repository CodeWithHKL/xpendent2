import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/transaction_model.dart';
import '../models/goal_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // =========================================================
  // USER PROFILE & AVATAR
  // =========================================================

  Stream<DocumentSnapshot<Map<String, dynamic>>> getUserProfile(String userId) {
    return _db.collection('users').doc(userId).snapshots();
  }

  Future<void> updateUserPersonalInfo(
      String userId, {
        required String displayName,
        required String email,
      }) async {
    await _db.collection('users').doc(userId).set({
      'displayName': displayName,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateUserProfilePicture(String userId, String base64Image) async {
    await _db.collection('users').doc(userId).set({
      'profilePicture': base64Image,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteUserProfilePicture(String userId) async {
    await _db.collection('users').doc(userId).update({
      'profilePicture': FieldValue.delete(),
    });
  }

  // =========================================================
  // TRANSACTIONS
  // =========================================================

  Stream<List<TransactionModel>> getTransactions(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => TransactionModel.fromFirestore(doc))
        .toList());
  }

  Future<void> addTransaction(String userId, TransactionModel tx) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .add(tx.toMap());
  }

  Future<void> deleteTransaction(String userId, String txId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .doc(txId)
        .delete();
  }

  // =========================================================
  // BUDGETS (MONTHLY CATEGORY BUDGETS & TRANSFERS)
  // =========================================================

  Stream<Map<String, double>> getMonthlyBudgets(
      String userId, int year, int month) {
    final String docId = '${year}_$month';
    return _db
        .collection('users')
        .doc(userId)
        .collection('budgets')
        .doc(docId)
        .snapshots()
        .map((snapshot) {
      final Map<String, double> result = {};
      if (!snapshot.exists || snapshot.data() == null) {
        return result;
      }
      final Map<String, dynamic> data =
      snapshot.data() as Map<String, dynamic>;
      data.forEach((key, value) {
        if (value is num) {
          result[key] = value.toDouble();
        }
      });
      return result;
    });
  }

  Future<void> setCategoryBudget(
      String userId, int year, int month, String category, double amount) async {
    final String docId = '${year}_$month';
    await _db
        .collection('users')
        .doc(userId)
        .collection('budgets')
        .doc(docId)
        .set({category: amount}, SetOptions(merge: true));
  }

  Future<void> transferBudget({
    required String userId,
    required int year,
    required int month,
    required String fromCategory,
    required String toCategory,
    required double transferAmount,
    required double currentFromAllocated,
    required double currentToAllocated,
  }) async {
    final String docId = '${year}_$month';
    final WriteBatch batch = _db.batch();
    final DocumentReference docRef =
    _db.collection('users').doc(userId).collection('budgets').doc(docId);

    final double updatedFrom =
    (currentFromAllocated - transferAmount).clamp(0.0, double.infinity);
    final double updatedTo = currentToAllocated + transferAmount;

    batch.set(
      docRef,
      {
        fromCategory: updatedFrom,
        toCategory: updatedTo,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  // =========================================================
  // GOALS (AUTOMATIC SUBCOLLECTION WRITES)
  // =========================================================

  Stream<List<GoalModel>> getGoals(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('goals')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => GoalModel.fromFirestore(doc)).toList());
  }

  Future<void> addGoal(String userId, GoalModel goal) async {
    DocumentReference userDoc = _db.collection('users').doc(userId);
    await userDoc.set({'lastUpdated': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await userDoc.collection('goals').add(goal.toMap());
  }

  Future<void> updateGoalProgress(
      String userId, String goalId, int newAmount) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('goals')
        .doc(goalId)
        .update({'currentAmount': newAmount});
  }

  Future<void> deleteGoal(String userId, String goalId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('goals')
        .doc(goalId)
        .delete();
  }

  // =========================================================
  // CUSTOM CATEGORIES
  // =========================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> getCustomCategories(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('custom_categories')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  Future<void> addCustomCategory({
    required String userId,
    required String title,
    required int iconCodePoint,
    required int colorValue,
    required String type,
  }) async {
    DocumentReference userDoc = _db.collection('users').doc(userId);
    await userDoc.set({'lastUpdated': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await userDoc.collection('custom_categories').add({
      'title': title,
      'iconCodePoint': iconCodePoint,
      'colorValue': colorValue,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCustomCategory(String userId, String categoryId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('custom_categories')
        .doc(categoryId)
        .delete();
  }
}
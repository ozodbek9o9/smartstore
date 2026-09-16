import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Provides the authenticated shop's Firestore root and business collections.
///
/// Keeping this path in one place prevents a feature from accidentally reading
/// or writing another shop's records.
class TenantFirestore {
  TenantFirestore._();

  static String get uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw const UnauthenticatedUserException();
    return uid;
  }

  static DocumentReference<Map<String, dynamic>> get userDocument =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  static DocumentReference<Map<String, dynamic>> usernameDocument(
    String username,
  ) => FirebaseFirestore.instance
      .collection('usernames')
      .doc(username.trim().toLowerCase());

  static CollectionReference<Map<String, dynamic>> collection(String name) =>
      userDocument.collection(name);

  static CollectionReference<Map<String, dynamic>> get products =>
      collection('products');
  static CollectionReference<Map<String, dynamic>> get categories =>
      collection('categories');
  static CollectionReference<Map<String, dynamic>> get customers =>
      collection('customers');

  static CollectionReference<Map<String, dynamic>> customerDebts(
    String customerId,
  ) => customers.doc(customerId).collection('debts');

  static CollectionReference<Map<String, dynamic>> customerPayments(
    String customerId,
  ) => customers.doc(customerId).collection('payments');

  static CollectionReference<Map<String, dynamic>> get sales =>
      collection('sales');
  static CollectionReference<Map<String, dynamic>> get sellingCarts =>
      collection('sellingCarts');
  static CollectionReference<Map<String, dynamic>> get draftProducts =>
      collection('draft_products');
  static CollectionReference<Map<String, dynamic>> get settings =>
      collection('settings');

  static CollectionReference<Map<String, dynamic>> get inventoryEntries =>
      collection('inventory_entries');

  static CollectionReference<Map<String, dynamic>> get dailySummaries =>
      collection('daily_summaries');

  static CollectionReference<Map<String, dynamic>> get weeklySummaries =>
      collection('weekly_summaries');
}

class UnauthenticatedUserException implements Exception {
  const UnauthenticatedUserException();

  @override
  String toString() => 'An authenticated Firebase user is required.';
}

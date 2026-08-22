import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/pos_models.dart';
import '../utils/tenant_firestore.dart';

class ProductStockException implements Exception {
  final String code;
  final String productName;

  ProductStockException(this.code, this.productName);

  @override
  String toString() => '$code:$productName';
}

class PosRepository {
  Future<PosProduct?> fetchProductByBarcode(String barcode) async {
    if (barcode.isEmpty) return null;

    final trimmedBarcode = barcode.trim();
    final query = await TenantFirestore.products
        .where('barcode', isEqualTo: trimmedBarcode)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return PosProduct.fromFirestore(query.docs.first);
    }

    final numericBarcode = num.tryParse(trimmedBarcode);
    if (numericBarcode != null) {
      final numericQuery = await TenantFirestore.products
          .where('barcode', isEqualTo: numericBarcode)
          .limit(1)
          .get();
      if (numericQuery.docs.isNotEmpty) {
        return PosProduct.fromFirestore(numericQuery.docs.first);
      }
    }

    return null;
  }

  Future<List<PosProduct>> searchProductsByName(String queryText) async {
    final query = queryText.trim();
    if (query.isEmpty) return [];

    final normalized = query.toLowerCase();
    final capitalized = query.length > 1
        ? '${query[0].toUpperCase()}${query.substring(1).toLowerCase()}'
        : query.toUpperCase();

    final nameFields = ['name', 'productName'];
    final lowerFields = ['nameLower', 'productNameLower'];
    final queryVariants = <String>{query, capitalized};

    final results = <PosProduct>[];
    final seenIds = <String>{};

    for (final field in nameFields) {
      for (final value in queryVariants) {
        if (value.isEmpty) continue;
        try {
          final snapshot = await TenantFirestore.products
              .where(field, isGreaterThanOrEqualTo: value)
              .where(field, isLessThanOrEqualTo: '$value\uf8ff')
              .orderBy(field)
              .limit(25)
              .get();

          for (final doc in snapshot.docs) {
            final product = PosProduct.fromFirestore(doc);
            if (seenIds.add(product.id) &&
                product.productName.toLowerCase().contains(normalized)) {
              results.add(product);
            }
          }

          if (results.length >= 25) break;
        } catch (_) {
          continue;
        }
      }
      if (results.length >= 25) break;
    }

    if (results.isEmpty) {
      for (final field in lowerFields) {
        try {
          final snapshot = await TenantFirestore.products
              .where(field, isGreaterThanOrEqualTo: normalized)
              .where(field, isLessThanOrEqualTo: '$normalized\uf8ff')
              .orderBy(field)
              .limit(25)
              .get();

          for (final doc in snapshot.docs) {
            final product = PosProduct.fromFirestore(doc);
            if (seenIds.add(product.id)) {
              results.add(product);
            }
          }

          if (results.length >= 25) break;
        } catch (_) {
          continue;
        }
      }
    }

    if (results.isEmpty && RegExp(r'^[0-9]+$').hasMatch(query)) {
      final barcodeProduct = await fetchProductByBarcode(query);
      if (barcodeProduct != null) {
        results.add(barcodeProduct);
      }
    }

    return results;
  }

  // Mahsulot stockini yangilash
  Future<void> updateProductStock(String productId, int newQuantity) async {
    try {
      await TenantFirestore.products
          .doc(productId)
          .update({
            'quantity': newQuantity,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      if (kDebugMode) {
        print('Product stock updated: $productId -> $newQuantity');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating product stock: $e');
      }
      throw Exception('Failed to update product stock: $e');
    }
  }

  // Savdo rekordini saqlash
  Future<void> saveSaleRecord(Map<String, dynamic> saleData) async {
    try {
      await TenantFirestore.sales.add(saleData);
      if (kDebugMode) {
        print('Sale record saved successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving sale record: $e');
      }
      throw Exception('Failed to save sale record: $e');
    }
  }
}

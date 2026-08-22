import 'package:cloud_firestore/cloud_firestore.dart';

class PosProduct {
  final String id;
  final String productName;
  final String barcode;
  final String category;
  final int quantity; // num -> int ga o'zgartirildi
  final num originalPrice;
  final num sellingPrice;
  final num profit;
  final String? imageUrl;

  PosProduct({
    required this.id,
    required this.productName,
    required this.barcode,
    required this.category,
    required this.quantity,
    required this.originalPrice,
    required this.sellingPrice,
    required this.profit,
    this.imageUrl,
  });

  factory PosProduct.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    num parseNumber(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value;
      return num.tryParse(value.toString()) ?? 0;
    }

    final String productName =
        data['productName']?.toString().trim() ??
        data['name']?.toString().trim() ??
        '';
    final String barcode = data['barcode']?.toString().trim() ?? '';
    final String category =
        data['category']?.toString().trim() ??
        data['type']?.toString().trim() ??
        '';
    final String? imageUrl =
        data['image']?.toString().trim() ?? data['imageUrl']?.toString().trim();

    // quantity ni int ga o'tkazamiz
    final quantityValue = parseNumber(data['quantity']);
    final int quantity = quantityValue is int
        ? quantityValue
        : quantityValue.toInt();

    return PosProduct(
      id: doc.id,
      productName: productName,
      barcode: barcode,
      category: category,
      quantity: quantity,
      originalPrice: parseNumber(data['originalPrice'] ?? data['costPrice']),
      sellingPrice: parseNumber(data['sellingPrice'] ?? data['salePrice']),
      profit: parseNumber(data['profit']),
      imageUrl: imageUrl,
    );
  }
}

class CartItem {
  final PosProduct product;
  int quantity;

  CartItem({required this.product, required this.quantity});

  num get lineTotal => product.sellingPrice * quantity;
}

class CustomerDebt {
  final String id;
  final String productName;
  final num? quantity;
  final num amount;
  final DateTime purchaseDate;
  final String? productId;

  CustomerDebt({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.amount,
    required this.purchaseDate,
    this.productId,
  });

  factory CustomerDebt.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return CustomerDebt(
      id: doc.id,
      productName: data['productName'] ?? 'Unknown',
      quantity: data['quantity'] as num?,
      amount: data['amount'] ?? 0,
      purchaseDate: parseDate(data['purchaseDate'] ?? data['timestamp']),
      productId: data['productId'],
    );
  }
}

class CustomerPayment {
  final String id;
  final String productName;
  final num? quantity;
  final num amount;
  final DateTime paymentDate;
  final bool isFullPayment;

  CustomerPayment({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.amount,
    required this.paymentDate,
    this.isFullPayment = false,
  });

  factory CustomerPayment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return CustomerPayment(
      id: doc.id,
      productName: data['productName'] ?? '',
      quantity: data['quantity'] as num?,
      amount: data['amount'] ?? 0,
      paymentDate: parseDate(data['paymentDate'] ?? data['timestamp']),
      isFullPayment: data['isFullPayment'] ?? false,
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/tenant_firestore.dart';

class SaleSyncItem {
  const SaleSyncItem({
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantity,
    required this.originalPrice,
    required this.sellingPrice,
  });

  final String productId;
  final String productName;
  final String category;
  final int quantity;
  final num originalPrice;
  final num sellingPrice;

  num get total => sellingPrice * quantity;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'productName': productName,
    'category': category,
    'quantity': quantity,
    'originalPrice': originalPrice,
    'sellingPrice': sellingPrice,
  };

  factory SaleSyncItem.fromJson(Map<String, dynamic> json) => SaleSyncItem(
    productId: json['productId']?.toString() ?? '',
    productName: json['productName']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    originalPrice: json['originalPrice'] as num? ?? 0,
    sellingPrice: json['sellingPrice'] as num? ?? 0,
  );
}

class QueuedSale {
  const QueuedSale({
    required this.id,
    required this.ownerUid,
    required this.createdAt,
    required this.items,
    required this.paymentType,
    required this.isDebtSale,
    required this.username,
    this.receiptNumber,
    this.customerId,
    this.customerName,
  });

  final String id;
  final String ownerUid;
  final DateTime createdAt;
  final List<SaleSyncItem> items;
  final String paymentType;
  final bool isDebtSale;
  final String username;
  final String? receiptNumber;
  final String? customerId;
  final String? customerName;

  num get total =>
      items.fold<num>(0, (runningTotal, item) => runningTotal + item.total);

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerUid': ownerUid,
    'createdAt': createdAt.toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(),
    'paymentType': paymentType,
    'isDebtSale': isDebtSale,
    'username': username,
    'receiptNumber': receiptNumber,
    'customerId': customerId,
    'customerName': customerName,
  };

  factory QueuedSale.fromJson(Map<String, dynamic> json) => QueuedSale(
    id: json['id']?.toString() ?? '',
    ownerUid: json['ownerUid']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    items: (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => SaleSyncItem.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    paymentType: json['paymentType']?.toString() ?? 'cash',
    isDebtSale: json['isDebtSale'] == true,
    username: json['username']?.toString() ?? 'Unknown',
    receiptNumber: json['receiptNumber']?.toString(),
    customerId: json['customerId']?.toString(),
    customerName: json['customerName']?.toString(),
  );
}

class OfflineSalesQueue extends ChangeNotifier {
  OfflineSalesQueue._();

  static final instance = OfflineSalesQueue._();
  static const _storagePrefix = 'smartstore_pending_sales_';

  Future<void> _queueTail = Future<void>.value();
  bool _isSyncing = false;
  bool _isOnline = true;
  bool _offlineModeEnabled = false;
  int _pendingCount = 0;
  String? _lastSyncError;

  bool get isOnline => _isOnline;
  bool get isOfflineModeEnabled => _offlineModeEnabled;
  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingCount;
  String? get lastSyncError => _lastSyncError;

  void setConnectivityStatus(bool isOnline) {
    if (_isOnline == isOnline) return;
    _isOnline = isOnline;
    notifyListeners();
  }

  void setOfflineModeEnabled(bool enabled) {
    if (_offlineModeEnabled == enabled) return;
    _offlineModeEnabled = enabled;
    notifyListeners();
  }

  Future<T> _withQueueLock<T>(Future<T> Function() action) async {
    final previous = _queueTail;
    final release = Completer<void>();
    _queueTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  Future<void> enqueue(QueuedSale sale) => _withQueueLock(() async {
    final preferences = await SharedPreferences.getInstance();
    final queue = _readQueue(preferences, sale.ownerUid);
    if (queue.any((queued) => queued.id == sale.id)) return;
    queue.add(sale);
    await _writeQueue(preferences, sale.ownerUid, queue);
    _pendingCount = queue.length;
    _lastSyncError = null;
    notifyListeners();
  });

  Future<Map<String, int>> pendingQuantities(String ownerUid) =>
      _withQueueLock(() async {
        final preferences = await SharedPreferences.getInstance();
        final pendingSales = _readQueue(preferences, ownerUid);
        if (_pendingCount != pendingSales.length) {
          _pendingCount = pendingSales.length;
          notifyListeners();
        }
        final result = <String, int>{};
        for (final sale in pendingSales) {
          for (final item in sale.items) {
            result.update(
              item.productId,
              (quantity) => quantity + item.quantity,
              ifAbsent: () => item.quantity,
            );
          }
        }
        return result;
      });

  Future<int> refreshPendingCount(String ownerUid) => _withQueueLock(() async {
    final preferences = await SharedPreferences.getInstance();
    final count = _readQueue(preferences, ownerUid).length;
    if (_pendingCount != count) {
      _pendingCount = count;
      notifyListeners();
    }
    return count;
  });

  Future<bool> containsSale(String ownerUid, String saleId) => _withQueueLock(
    () async {
      final preferences = await SharedPreferences.getInstance();
      return _readQueue(preferences, ownerUid).any((sale) => sale.id == saleId);
    },
  );

  Future<int> syncPendingSales() async {
    if (_isSyncing || !_isOnline || _offlineModeEnabled) return 0;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return 0;

    _isSyncing = true;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      final pending = await _withQueueLock(
        () async => _readQueue(preferences, uid),
      );
      _pendingCount = pending.length;
      _lastSyncError = null;
      notifyListeners();
      var synced = 0;

      for (final sale in pending) {
        if (FirebaseAuth.instance.currentUser?.uid != uid) break;
        try {
          await SaleCommitService.instance.commit(sale);
        } catch (error, stackTrace) {
          _lastSyncError = error.toString();
          debugPrint('Offline sale ${sale.id} is waiting to sync: $error');
          debugPrintStack(stackTrace: stackTrace);
          notifyListeners();
          break;
        }

        await _withQueueLock(() async {
          final latest = _readQueue(preferences, uid)
            ..removeWhere((queued) => queued.id == sale.id);
          await _writeQueue(preferences, uid, latest);
          _pendingCount = latest.length;
          _lastSyncError = null;
          notifyListeners();
        });
        synced++;
      }
      return synced;
    } catch (error, stackTrace) {
      _lastSyncError = error.toString();
      debugPrint('Unable to load pending offline sales: $error');
      debugPrintStack(stackTrace: stackTrace);
      notifyListeners();
      return 0;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  List<QueuedSale> _readQueue(SharedPreferences preferences, String uid) {
    final raw = preferences.getString('$_storagePrefix$uid');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => QueuedSale.fromJson(Map<String, dynamic>.from(item)))
          .where((sale) => sale.id.isNotEmpty && sale.ownerUid == uid)
          .toList();
    } catch (error) {
      debugPrint('Unable to read pending offline sales: $error');
      throw FormatException(
        'Pending offline sales queue is unreadable.',
        error,
      );
    }
  }

  Future<void> _writeQueue(
    SharedPreferences preferences,
    String uid,
    List<QueuedSale> queue,
  ) async {
    final key = '$_storagePrefix$uid';
    if (queue.isEmpty) {
      await preferences.remove(key);
      return;
    }
    final saved = await preferences.setString(
      key,
      jsonEncode(queue.map((sale) => sale.toJson()).toList()),
    );
    if (!saved) throw StateError('Could not persist pending offline sales.');
  }
}

class SaleCommitService {
  SaleCommitService._();

  static final instance = SaleCommitService._();

  Future<void> commit(QueuedSale sale) async {
    final activeUid = FirebaseAuth.instance.currentUser?.uid;
    if (activeUid == null || activeUid != sale.ownerUid) {
      throw StateError('Pending sale belongs to another signed-in account.');
    }
    if (sale.items.isEmpty) throw StateError('Cannot sync an empty sale.');

    final firestore = FirebaseFirestore.instance;
    final saleReference = TenantFirestore.sales.doc(sale.id);
    final receiptReference = TenantFirestore.settings.doc('receipt');
    final productReferences = sale.items
        .map((item) => TenantFirestore.products.doc(item.productId))
        .toList(growable: false);
    final customerReference = sale.isDebtSale && sale.customerId != null
        ? TenantFirestore.customers.doc(sale.customerId)
        : null;
    final total = sale.total;

    await firestore.runTransaction((transaction) async {
      final saleSnapshot = await transaction.get(saleReference);
      if (saleSnapshot.exists) return;

      final productSnapshots = await Future.wait(
        productReferences.map(transaction.get),
      );
      final customerSnapshot = customerReference == null
          ? null
          : await transaction.get(customerReference);
      final receiptSnapshot = sale.receiptNumber == null
          ? await transaction.get(receiptReference)
          : null;

      final receiptNumber =
          sale.receiptNumber ??
          _nextReceiptNumber(receiptSnapshot?.data()?['lastReceiptNumber']);
      final saleTimestamp = Timestamp.fromDate(sale.createdAt);

      for (var index = 0; index < sale.items.length; index++) {
        final item = sale.items[index];
        final productSnapshot = productSnapshots[index];
        if (!productSnapshot.exists) continue;
        final available =
            (productSnapshot.data()?['quantity'] as num?)?.toInt() ?? 0;
        final newQuantity = available - item.quantity;
        transaction.update(productReferences[index], {
          'quantity': newQuantity,
          'status': newQuantity <= 0
              ? 'tugagan'
              : newQuantity <= 10
              ? 'kam'
              : 'normal',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      final customerExists = customerSnapshot?.exists ?? false;
      if (customerReference != null && customerExists) {
        final customerData = customerSnapshot!.data() ?? {};
        final currentTotal = customerData['totalDebt'] ?? 0;
        final currentPaid = customerData['paidDebt'] ?? 0;
        final currentRemaining =
            customerData['remainingDebt'] ?? (currentTotal - currentPaid);
        final nextRemaining = currentRemaining + total;
        transaction.update(customerReference, {
          'totalDebt': nextRemaining,
          'remainingDebt': nextRemaining,
          'paidDebt': currentRemaining > 0 ? currentPaid : 0,
          'lastActivity': FieldValue.serverTimestamp(),
        });

        for (var index = 0; index < sale.items.length; index++) {
          final item = sale.items[index];
          final debtReference = TenantFirestore.customerDebts(
            sale.customerId!,
          ).doc('${sale.id}_$index');
          transaction.set(debtReference, {
            'productId': item.productId,
            'productName': item.productName,
            'quantity': item.quantity,
            'amount': item.total.toDouble(),
            'purchaseDate': saleTimestamp,
          });
        }
      }

      if (sale.receiptNumber == null) {
        transaction.set(receiptReference, {
          'lastReceiptNumber': int.parse(receiptNumber),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final itemData = sale.items
          .map((item) {
            final profitPerUnit = item.sellingPrice - item.originalPrice;
            return {
              'productId': item.productId,
              'productName': item.productName,
              'category': item.category,
              'quantity': item.quantity,
              'originalPrice': item.originalPrice.toDouble(),
              'price': item.sellingPrice.toDouble(),
              'profitPerUnit': profitPerUnit,
              'totalProfit': profitPerUnit * item.quantity,
              'total': item.total.toDouble(),
              'originalTotal': (item.originalPrice * item.quantity).toDouble(),
            };
          })
          .toList(growable: false);
      final originalCostTotal = sale.items.fold<num>(
        0,
        (runningTotal, item) =>
            runningTotal + item.originalPrice * item.quantity,
      );
      final profitTotal = sale.items.fold<num>(
        0,
        (runningTotal, item) =>
            runningTotal +
            (item.sellingPrice - item.originalPrice) * item.quantity,
      );
      transaction.set(saleReference, {
        'items': itemData,
        'subtotal': total.toDouble(),
        'discount': 0,
        'total': total.toDouble(),
        'totalAmount': total.toDouble(),
        'originalCostTotal': originalCostTotal.toDouble(),
        'profitTotal': profitTotal.toDouble(),
        'receiptNumber': receiptNumber,
        'paymentType': sale.paymentType,
        'isDebtSale': sale.isDebtSale,
        'customerId': sale.customerId,
        'customerName': sale.customerName,
        'customerRecordMissing': sale.isDebtSale && !customerExists,
        'missingProductIds': [
          for (var index = 0; index < productSnapshots.length; index++)
            if (!productSnapshots[index].exists) sale.items[index].productId,
        ],
        'user': sale.username,
        'timestamp': saleTimestamp,
        'status': sale.isDebtSale ? 'debt' : 'completed',
      });

      for (var index = 0; index < sale.items.length; index++) {
        final item = sale.items[index];
        final entryReference = TenantFirestore.inventoryEntries.doc(
          '${sale.id}_$index',
        );
        transaction.set(entryReference, {
          'type': 'outgoing',
          'saleId': sale.id,
          'productId': item.productId,
          'productName': item.productName,
          'category': item.category,
          'quantity': item.quantity,
          'originalPrice': item.originalPrice.toDouble(),
          'sellingPrice': item.sellingPrice.toDouble(),
          'totalCostValue': (item.originalPrice * item.quantity).toDouble(),
          'totalSaleValue': item.total.toDouble(),
          'profitPerUnit': (item.sellingPrice - item.originalPrice).toDouble(),
          'totalProfit':
              ((item.sellingPrice - item.originalPrice) * item.quantity)
                  .toDouble(),
          'user': sale.username,
          'paymentType': sale.paymentType,
          'isDebtSale': sale.isDebtSale,
          'customerId': sale.customerId,
          'customerName': sale.customerName,
          'timestamp': saleTimestamp,
        });
      }
    });
  }

  String _nextReceiptNumber(dynamic rawNumber) {
    final currentNumber = rawNumber is num
        ? rawNumber.toInt()
        : int.tryParse(rawNumber?.toString() ?? '') ?? 0;
    return (currentNumber + 1).toString().padLeft(6, '0');
  }
}

class SaleSyncStockException implements Exception {
  const SaleSyncStockException(this.productName);

  final String productName;

  @override
  String toString() => 'Not enough stock to sync sale for $productName.';
}

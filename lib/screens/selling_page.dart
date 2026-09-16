import 'dart:async';
import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../utils/tenant_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'theme_controller.dart';
import '../models/pos_models.dart';
import '../services/pos_service.dart';

class SalePaymentSelection {
  const SalePaymentSelection({
    required this.receiptNumber,
    required this.paymentType,
  });

  final String receiptNumber;
  final String paymentType;
}

class SellingPage extends StatefulWidget {
  const SellingPage({super.key});

  @override
  State<SellingPage> createState() => _SellingPageState();
}

class _SellingPageState extends State<SellingPage> {
  late final TextEditingController _customerController;
  late final PosCartService _cartService;

  final ScrollController _cartScrollController = ScrollController();
  Timer? _cartSyncDebounce;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _customersSub;
  DocumentReference<Map<String, dynamic>>? _cartDocument;
  Future<void> _cartWriteQueue = Future.value();

  // ── Barcode scanner support ──
  final StringBuffer _barcodeBuffer = StringBuffer();
  Timer? _barcodeResetTimer;
  DateTime _lastBarcodeKeyTime = DateTime(2000);
  bool _isScannerActive = false;

  final Queue<String> _barcodeQueue = Queue<String>();
  bool _isBarcodeProcessing = false;

  // ── Local barcode cache ──
  final Map<String, PosProduct> _barcodeCache = {};
  bool _isBarcodeCacheLoaded = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _productsSub;

  List<_PosCustomer> _customers = const [];
  bool _isProcessingSale = false;
  bool _isDebtSale = false;
  bool _isCartReady = false;
  int _cartWriteGeneration = 0;
  _PosCustomer? _selectedCustomer;

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    _customerController = TextEditingController();
    _cartService = PosCartService();

    _cartService.addListener(_onCartChanged);
    _subscribeToCustomers();
    _loadBarcodeCache();
    unawaited(_initializeFirebaseCart());

    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _cartSyncDebounce?.cancel();
    _barcodeResetTimer?.cancel();
    _productsSub?.cancel();
    ++_cartWriteGeneration;
    _customersSub?.cancel();
    _customerController.dispose();
    _cartService.removeListener(_onCartChanged);
    _cartService.clearCart();
    _cartService.dispose();
    unawaited(_deleteActiveCartAfterPendingWrites());
    _cartScrollController.dispose();
    super.dispose();
  }

  String _t(String key, {List<String>? args}) =>
      'selling_pos.$key'.tr(args: args);

  Future<void> _loadBarcodeCache() async {
    if (_isBarcodeCacheLoaded) return;

    _productsSub = TenantFirestore.products.snapshots().listen((snapshot) {
      final cache = <String, PosProduct>{};
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final barcode = data['barcode']?.toString().trim();
          if (barcode != null && barcode.isNotEmpty) {
            final product = PosProduct(
              id: doc.id,
              productName: data['productName']?.toString() ?? '',
              barcode: barcode,
              category: data['category']?.toString() ?? '',
              quantity: (data['quantity'] as num?)?.toInt() ?? 0,
              originalPrice: (data['originalPrice'] as num?)?.toDouble() ?? 0,
              sellingPrice: (data['sellingPrice'] as num?)?.toDouble() ?? 0,
              profit: (data['profit'] as num?)?.toDouble() ?? 0,
              imageUrl:
                  data['image']?.toString() ?? data['imageUrl']?.toString(),
            );
            cache[barcode] = product;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _barcodeCache
            ..clear()
            ..addAll(cache);
          _isBarcodeCacheLoaded = true;
        });
      }
    });
  }

  PosProduct? _findProductByBarcode(String barcode) {
    return _barcodeCache[barcode.trim()];
  }

  Future<void> _initializeFirebaseCart() async {
    if (!mounted) return;
    final document = TenantFirestore.sellingCarts.doc('active');
    _cartDocument = document;
    try {
      await document.delete();
    } catch (_) {}
    if (mounted) setState(() => _isCartReady = true);
  }

  Future<void> _deleteActiveCartAfterPendingWrites() async {
    final document = _cartDocument;
    if (document == null) return;
    try {
      await _cartWriteQueue;
      await document.delete();
    } catch (_) {}
  }

  Map<String, dynamic> _cartPayload() => {
    'items': _cartService.items
        .map(
          (item) => {
            'productId': item.product.id,
            'productName': item.product.productName,
            'barcode': item.product.barcode,
            'quantity': item.quantity,
            'unitPrice': item.product.sellingPrice.toDouble(),
          },
        )
        .toList(),
    'isDebtSale': _isDebtSale,
    'selectedCustomerId': _selectedCustomer?.id,
    'selectedCustomerName': _selectedCustomer?.fullName,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  void _scheduleCartSync() {
    if (_isProcessingSale || !_isCartReady || _cartDocument == null) return;
    _cartSyncDebounce?.cancel();
    final generation = ++_cartWriteGeneration;
    _cartSyncDebounce = Timer(const Duration(milliseconds: 110), () {
      _queueCartWrite(generation, _cartPayload());
    });
  }

  void _queueCartWrite(int generation, Map<String, dynamic> payload) {
    final document = _cartDocument;
    if (document == null) return;
    _cartWriteQueue = _cartWriteQueue.then(
      (_) => _writeCart(document, generation, payload),
      onError: (_) => _writeCart(document, generation, payload),
    );
  }

  Future<void> _writeCart(
    DocumentReference<Map<String, dynamic>> document,
    int generation,
    Map<String, dynamic> payload,
  ) async {
    if (_isProcessingSale || generation != _cartWriteGeneration) return;
    try {
      await document.set(payload, SetOptions(merge: true));
    } catch (_) {
      if (mounted && !_isProcessingSale) _showError(_t('cart_sync_failed'));
    }
  }

  void _subscribeToCustomers() {
    _customersSub = TenantFirestore.customers.snapshots().listen((snapshot) {
      final customers = snapshot.docs.map(_PosCustomer.fromFirestore).toList()
        ..sort(
          (first, second) => first.fullName.toLowerCase().compareTo(
            second.fullName.toLowerCase(),
          ),
        );
      if (mounted) setState(() => _customers = customers);
    });
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
    _scheduleCartSync();
  }

  void _addToCart(PosProduct product) {
    if (!_cartService.addOrIncrementItem(product)) {
      _showError(
        _t('insufficient_stock_with_name', args: [product.productName]),
      );
      return;
    }

    if (mounted) setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cartScrollController.hasClients) {
        _cartScrollController.animateTo(
          _cartScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _selectCustomer(_PosCustomer customer) {
    setState(() {
      _selectedCustomer = customer;
      _customerController.text = customer.fullName;
    });
    _scheduleCartSync();
  }

  void _onCustomerChanged(String value) {
    setState(() {
      if (_selectedCustomer != null && value != _selectedCustomer!.fullName) {
        _selectedCustomer = null;
      }
    });
    _scheduleCartSync();
  }

  List<_PosCustomer> get _customerSuggestions {
    final query = _customerController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _customers
        .where((customer) => customer.fullName.toLowerCase().contains(query))
        .take(5)
        .toList();
  }

  Future<void> _showAddCustomerDialog() async {
    final nameController = TextEditingController();
    final createdCustomer = await showDialog<_PosCustomer>(
      context: context,
      builder: (dialogContext) {
        var isSaving = false;
        return StatefulBuilder(
          builder: (context, setModalState) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('add_customer_title'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t('add_customer_subtitle'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDecoration(_t('customer_name')),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSaving
                                ? null
                                : () => Navigator.pop(dialogContext),
                            child: Text(_t('cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final name = nameController.text.trim();
                                    if (name.isEmpty) {
                                      _showError(_t('customer_name_required'));
                                      return;
                                    }
                                    setModalState(() => isSaving = true);
                                    try {
                                      final document = await TenantFirestore
                                          .customers
                                          .add({
                                            'fullName': name,
                                            'name': name,
                                            'status': 'doimiy',
                                            'totalDebt': 0,
                                            'paidDebt': 0,
                                            'remainingDebt': 0,
                                            'lastActivity':
                                                FieldValue.serverTimestamp(),
                                            'createdAt':
                                                FieldValue.serverTimestamp(),
                                          });
                                      if (dialogContext.mounted) {
                                        Navigator.pop(
                                          dialogContext,
                                          _PosCustomer(
                                            id: document.id,
                                            fullName: name,
                                          ),
                                        );
                                      }
                                    } catch (_) {
                                      setModalState(() => isSaving = false);
                                      _showError(_t('customer_create_failed'));
                                    }
                                  },
                            child: isSaving
                                ? SizedBox(
                                    height: 19,
                                    width: 19,
                                    child: CircularProgressIndicator(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_t('select')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    nameController.dispose();
    if (createdCustomer != null && mounted) _selectCustomer(createdCustomer);
  }

  Future<void> _clearCart() async {
    if (_cartService.items.isEmpty) return;
    final colors = Theme.of(context).colorScheme;
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('clear_cart_title')),
        content: Text(_t('clear_cart_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            child: Text(_t('clear')),
          ),
        ],
      ),
    );
    if (shouldClear == true) _cartService.clearCart();
  }

  Future<void> _showConfirmSaleDialog() async {
    final items = List<CartItem>.from(_cartService.items);
    if (items.isEmpty || _isProcessingSale || _cartDocument == null) return;
    if (_isDebtSale && _selectedCustomer == null) {
      _showError(_t('debt_customer_required'));
      return;
    }
    for (final item in items) {
      if (item.quantity > item.product.quantity) {
        _showError(
          _t('insufficient_stock_with_name', args: [item.product.productName]),
        );
        return;
      }
    }

    final document = TenantFirestore.settings.doc('receipt');
    final receiptNumber = await _reserveSaleNumber(document);
    if (!mounted) return;
    final payment = SalePaymentSelection(
      receiptNumber: receiptNumber,
      paymentType: 'cash',
    );
    await _completeSale(payment);
  }

  Future<void> _completeSale(SalePaymentSelection sale) async {
    final items = List<CartItem>.from(_cartService.items);
    final cartDocument = _cartDocument;
    if (items.isEmpty || _isProcessingSale || cartDocument == null) return;
    if (_isDebtSale && _selectedCustomer == null) {
      _showError(_t('debt_customer_required'));
      return;
    }
    for (final item in items) {
      if (item.quantity > item.product.quantity) {
        _showError(
          _t('insufficient_stock_with_name', args: [item.product.productName]),
        );
        return;
      }
    }

    setState(() => _isProcessingSale = true);
    _cartSyncDebounce?.cancel();
    ++_cartWriteGeneration;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );

    var saleSucceeded = false;
    try {
      await _cartWriteQueue;

      final total = _cartService.subtotal;
      final salesDocument = TenantFirestore.sales.doc();
      final productReferences = items
          .map((item) => TenantFirestore.products.doc(item.product.id))
          .toList(growable: false);

      String username = 'Unknown';
      try {
        final profile = await TenantFirestore.userDocument.get();
        username = (profile.data()?['username'] ?? 'Unknown').toString();
      } catch (_) {}

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final productSnapshots = await Future.wait(
          productReferences.map(transaction.get),
        );
        final customerReference = _isDebtSale
            ? TenantFirestore.customers.doc(_selectedCustomer!.id)
            : null;
        final customerSnapshot = customerReference == null
            ? null
            : await transaction.get(customerReference);

        for (var index = 0; index < items.length; index++) {
          final item = items[index];
          final productSnapshot = productSnapshots[index];
          final available =
              (productSnapshot.data()?['quantity'] as num?)?.toInt() ?? 0;
          if (!productSnapshot.exists || available < item.quantity) {
            throw ProductStockException(
              'insufficient_stock',
              item.product.productName,
            );
          }
        }
        if (customerSnapshot != null && !customerSnapshot.exists) {
          throw StateError('The selected customer no longer exists.');
        }

        for (var index = 0; index < items.length; index++) {
          final item = items[index];
          final available =
              (productSnapshots[index].data()?['quantity'] as num?)?.toInt() ??
              0;
          transaction.update(productReferences[index], {
            'quantity': available - item.quantity,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        if (customerReference != null) {
          transaction.update(customerReference, {
            'totalDebt': FieldValue.increment(total),
            'remainingDebt': FieldValue.increment(total),
            'lastActivity': FieldValue.serverTimestamp(),
          });

          for (final item in items) {
            final debtDoc = TenantFirestore.customerDebts(
              _selectedCustomer!.id,
            ).doc();
            transaction.set(debtDoc, {
              'productId': item.product.id,
              'productName': item.product.productName,
              'quantity': item.quantity,
              'amount': item.lineTotal.toDouble(),
              'purchaseDate': FieldValue.serverTimestamp(),
            });
          }
        }
        transaction.set(salesDocument, {
          'items': items.map((item) {
            final originalPrice = item.product.originalPrice.toDouble();
            final sellingPrice = item.product.sellingPrice.toDouble();
            final quantity = item.quantity;
            final profitPerUnit = sellingPrice - originalPrice;
            final totalProfit = profitPerUnit * quantity;
            return {
              'productId': item.product.id,
              'productName': item.product.productName,
              'quantity': quantity,
              'originalPrice': originalPrice,
              'price': sellingPrice,
              'profitPerUnit': profitPerUnit,
              'totalProfit': totalProfit,
              'total': item.lineTotal.toDouble(),
              'originalTotal': (originalPrice * quantity),
            };
          }).toList(),
          'subtotal': total.toDouble(),
          'discount': 0,
          'total': total.toDouble(),
          'totalAmount': total.toDouble(),
          'originalCostTotal': items
              .fold<num>(
                0,
                (sum, item) => sum + item.product.originalPrice * item.quantity,
              )
              .toDouble(),
          'profitTotal': items
              .fold<num>(
                0,
                (sum, item) =>
                    sum +
                    (item.product.sellingPrice - item.product.originalPrice) *
                        item.quantity,
              )
              .toDouble(),
          'receiptNumber': sale.receiptNumber,
          'paymentType': sale.paymentType,
          'isDebtSale': _isDebtSale,
          'customerId': _isDebtSale ? _selectedCustomer!.id : null,
          'customerName': _isDebtSale ? _selectedCustomer!.fullName : null,
          'user': username,
          'timestamp': FieldValue.serverTimestamp(),
          'status': _isDebtSale ? 'debt' : 'completed',
        });

        for (final item in items) {
          final entryRef = TenantFirestore.inventoryEntries.doc();
          final originalPrice = item.product.originalPrice.toDouble();
          final sellingPrice = item.product.sellingPrice.toDouble();
          final quantity = item.quantity;
          transaction.set(entryRef, {
            'type': 'outgoing',
            'saleId': salesDocument.id,
            'productId': item.product.id,
            'productName': item.product.productName,
            'quantity': quantity,
            'originalPrice': originalPrice,
            'sellingPrice': sellingPrice,
            'totalCostValue': (originalPrice * quantity),
            'totalSaleValue': (sellingPrice * quantity),
            'profitPerUnit': (sellingPrice - originalPrice),
            'totalProfit': ((sellingPrice - originalPrice) * quantity),
            'user': username,
            'paymentType': sale.paymentType,
            'isDebtSale': _isDebtSale,
            'customerId': _isDebtSale ? _selectedCustomer!.id : null,
            'customerName': _isDebtSale ? _selectedCustomer!.fullName : null,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }

        transaction.delete(cartDocument);
      });
      saleSucceeded = true;

      _cartService.clearCart();
      if (mounted) {
        setState(() {
          _isDebtSale = false;
          _selectedCustomer = null;
          _customerController.clear();
        });
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSuccess(_t('sale_completed'));
    } on ProductStockException catch (error) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showError(
          _t('insufficient_stock_with_name', args: [error.productName]),
        );
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showError(_t('sale_failed'));
      }
    } finally {
      if (mounted) setState(() => _isProcessingSale = false);
      if (!saleSucceeded) _scheduleCartSync();
    }
  }

  void _showError(String message) {
    final colors = Theme.of(context).colorScheme;
    _showMessage(message, colors.error, colors.onError);
  }

  void _showSuccess(String message) {
    final colors = Theme.of(context).colorScheme;
    _showMessage(message, colors.primary, colors.onPrimary);
  }

  void _showMessage(String message, Color background, Color foreground) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: foreground)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: background,
        ),
      );
  }

  // ── Barcode scanner ──
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    final key = event.logicalKey;
    final char = event.character;

    final bool isNumber = char != null && RegExp(r'^[0-9]$').hasMatch(char);
    final int timeGap = now.difference(_lastBarcodeKeyTime).inMilliseconds;
    final bool isEndKey =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.escape;

    if (isEndKey) {
      final barcode = _barcodeBuffer.toString().trim();
      _barcodeBuffer.clear();
      _barcodeResetTimer?.cancel();

      if (barcode.length >= 6) {
        _handleBarcodeScanned(barcode);
        return true;
      }
      return false;
    }

    if (isNumber && timeGap < 180) {
      if (!_isScannerActive) {
        _isScannerActive = true;
      }

      _barcodeBuffer.write(char);
      _lastBarcodeKeyTime = now;

      _barcodeResetTimer?.cancel();
      _barcodeResetTimer = Timer(const Duration(milliseconds: 110), () {
        final barcode = _barcodeBuffer.toString().trim();
        if (barcode.length >= 6) {
          _handleBarcodeScanned(barcode);
        }
        _barcodeBuffer.clear();
        _isScannerActive = false;
      });

      return false;
    }

    if (isNumber && timeGap >= 180) {
      _barcodeBuffer.clear();
      _barcodeBuffer.write(char);
      _lastBarcodeKeyTime = now;
      if (_isScannerActive) {
        _isScannerActive = false;
      }
      return false;
    }

    if (!isNumber && char != null && char.isNotEmpty) {
      _barcodeBuffer.clear();
    }

    _lastBarcodeKeyTime = now;
    return false;
  }

  Future<void> _handleBarcodeScanned(String barcode) async {
    _barcodeQueue.add(barcode);
    if (_isBarcodeProcessing) return;
    _isBarcodeProcessing = true;

    while (_barcodeQueue.isNotEmpty) {
      final currentBarcode = _barcodeQueue.removeFirst();
      try {
        final product = _findProductByBarcode(currentBarcode);
        if (!mounted) break;
        if (product == null) {
          SystemSound.play(SystemSoundType.alert);
          continue;
        }
        _addToCart(product);
        SystemSound.play(SystemSoundType.click);
      } catch (_) {
        if (mounted) {
          SystemSound.play(SystemSoundType.alert);
        }
      }
    }

    _isBarcodeProcessing = false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final isDark = ThemeController.instance.isDarkMode;

        return Scaffold(
          backgroundColor: isDark ? colors.surface : colors.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ── Scanner Status ──
                  _buildScannerStatus(context),
                  const SizedBox(height: 12),

                  // ── MAIN CONTENT ──
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 980;

                        return Row(
                          children: [
                            // ── LEFT: Shopping Cart ──
                            Expanded(
                              flex: compact ? 1 : 7,
                              child: _buildShoppingCartPanel(context),
                            ),
                            const SizedBox(width: 16),
                            // ── RIGHT: Order Summary ──
                            Expanded(
                              flex: compact ? 1 : 3,
                              child: _buildOrderSummaryPanel(context),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScannerStatus(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = ThemeController.instance.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? colors.surfaceContainerHighest.withOpacity(0.15)
            : colors.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? colors.outlineVariant.withOpacity(0.15)
              : colors.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isScannerActive
                  ? colors.primary.withOpacity(isDark ? 0.2 : 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.qr_code_scanner_rounded,
              size: 20,
              color: _isScannerActive
                  ? colors.primary
                  : colors.onSurfaceVariant.withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _isScannerActive ? _t('scanner_active') : _t('scanner_prompt'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: _isScannerActive ? FontWeight.w700 : FontWeight.w500,
              color: _isScannerActive
                  ? colors.primary
                  : isDark
                  ? colors.onSurfaceVariant.withOpacity(0.6)
                  : colors.onSurfaceVariant.withOpacity(0.6),
            ),
          ),
          if (_isScannerActive) ...[
            const Spacer(),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShoppingCartPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final items = _cartService.items;
    final isDark = ThemeController.instance.isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colors.surfaceContainerHighest.withOpacity(0.1)
            : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? colors.outlineVariant.withOpacity(0.1)
              : colors.outlineVariant.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.15)
                : Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primary.withOpacity(isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.shopping_cart_rounded,
                    color: colors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _t('shopping_cart'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? colors.onSurface : colors.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    items.length.toString(),
                    style: TextStyle(
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Spacer(),
                if (items.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearCart,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: isDark
                          ? colors.error.withOpacity(0.8)
                          : colors.error,
                    ),
                    label: Text(
                      _t('clear_cart'),
                      style: TextStyle(
                        color: isDark
                            ? colors.error.withOpacity(0.8)
                            : colors.error,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: isDark
                ? colors.outlineVariant.withOpacity(0.2)
                : colors.outlineVariant.withOpacity(0.3),
          ),

          // ── Cart Items ──
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: isDark
                                ? colors.surfaceContainerHighest.withOpacity(
                                    0.2,
                                  )
                                : colors.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.shopping_cart_outlined,
                            size: 32,
                            color: isDark
                                ? colors.onSurfaceVariant.withOpacity(0.4)
                                : colors.onSurfaceVariant.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _t('cart_empty_title'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? colors.onSurfaceVariant
                                : colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _t('cart_empty_subtitle'),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? colors.onSurfaceVariant.withOpacity(0.6)
                                : colors.onSurfaceVariant.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _cartScrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _buildCartItemCard(context, item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(BuildContext context, CartItem item) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = ThemeController.instance.isDarkMode;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colors.surfaceContainerHighest.withOpacity(0.15)
            : colors.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? colors.outlineVariant.withOpacity(0.1)
              : colors.outlineVariant.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          // ── Product Image / Icon ──
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primary.withOpacity(isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.inventory_2_rounded,
              color: colors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),

          // ── Product Details ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.productName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? colors.onSurface : colors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _money(item.product.sellingPrice),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: isDark
                            ? colors.onSurfaceVariant.withOpacity(0.3)
                            : colors.onSurfaceVariant.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${_t('stock_quantity')}: ${item.product.quantity}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? colors.onSurfaceVariant.withOpacity(0.6)
                            : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Quantity Controls ──
          Row(
            children: [
              _roundQuantityButton(
                context,
                icon: Icons.remove_rounded,
                disabled: _isProcessingSale || item.quantity == 0,
                onTap: () {
                  if (item.quantity == 1) {
                    _cartService.removeItem(item.product);
                  } else {
                    _cartService.updateQuantity(
                      item.product,
                      item.quantity - 1,
                    );
                  }
                },
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 32,
                child: Text(
                  item.quantity.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isDark ? colors.onSurface : colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _roundQuantityButton(
                context,
                icon: Icons.add_rounded,
                filled: true,
                disabled:
                    item.quantity >= item.product.quantity || _isProcessingSale,
                onTap: () {
                  final updated = _cartService.updateQuantity(
                    item.product,
                    item.quantity + 1,
                  );
                  if (!updated) _showError(_t('insufficient_stock'));
                },
              ),
            ],
          ),

          const SizedBox(width: 12),

          // ── Total Price & Delete (yonma-yon) ──
          Row(
            children: [
              Text(
                _money(item.lineTotal),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _cartService.removeItem(item.product),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: isDark
                        ? colors.onSurfaceVariant.withOpacity(0.5)
                        : colors.onSurfaceVariant.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roundQuantityButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
    bool filled = false,
    bool disabled = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final isDark = ThemeController.instance.isDarkMode;

    final background = disabled
        ? (isDark
              ? colors.surfaceContainerHighest.withOpacity(0.2)
              : colors.surfaceContainerHighest)
        : (filled
              ? colors.primary
              : (isDark
                    ? colors.primaryContainer.withOpacity(0.15)
                    : colors.primaryContainer));

    final foreground = filled && !disabled
        ? colors.onPrimary
        : (disabled
              ? (isDark
                    ? colors.onSurfaceVariant.withOpacity(0.3)
                    : colors.onSurfaceVariant.withOpacity(0.3))
              : colors.primary);

    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: disabled ? null : onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 18, color: foreground),
        ),
      ),
    );
  }

  Widget _buildOrderSummaryPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = _cartService.subtotal;
    final items = _cartService.items;
    final isDark = ThemeController.instance.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark
            ? colors.surfaceContainerHighest.withOpacity(0.1)
            : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? colors.outlineVariant.withOpacity(0.1)
              : colors.outlineVariant.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.15)
                : Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // ── Shopping Cart Image ──
            Container(
              width: 120,
              height: 120,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: isDark
                  ? Image.asset(
                      'assets/shopping_cart_dark.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.shopping_cart_rounded,
                          color: colors.primary,
                          size: 56,
                        );
                      },
                    )
                  : Image.asset(
                      'assets/shopping_cart.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.shopping_cart_rounded,
                          color: colors.primary,
                          size: 56,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),

            // ── Order Total ──
            Text(
              _t('order_total'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? colors.onSurfaceVariant.withOpacity(0.6)
                    : colors.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _money(total),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: isDark ? colors.onSurface : colors.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 20),

            Divider(
              height: 1,
              color: isDark
                  ? colors.outlineVariant.withOpacity(0.2)
                  : colors.outlineVariant.withOpacity(0.3),
            ),
            const SizedBox(height: 16),

            // ── Subtotal ──
            _summaryRow(context, _t('subtotal'), _money(total)),
            const SizedBox(height: 6),
            _summaryRow(context, _t('tax'), _money(0)),
            const SizedBox(height: 12),

            Divider(
              height: 1,
              color: isDark
                  ? colors.outlineVariant.withOpacity(0.2)
                  : colors.outlineVariant.withOpacity(0.3),
            ),
            const SizedBox(height: 12),

            // ── Grand Total ──
            _summaryRow(context, _t('total'), _money(total), total: true),
            const SizedBox(height: 18),

            // ── Debt Sale ──
            _buildDebtSection(context),

            const SizedBox(height: 14),

            // ── Checkout Button ──
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: items.isEmpty || _isProcessingSale || !_isCartReady
                    ? null
                    : _showConfirmSaleDialog,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: isDark ? 0 : 2,
                  backgroundColor: colors.primary,
                  disabledBackgroundColor: isDark
                      ? colors.onSurfaceVariant.withOpacity(0.08)
                      : colors.onSurfaceVariant.withOpacity(0.08),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isProcessingSale)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: colors.onPrimary,
                          strokeWidth: 2,
                        ),
                      )
                    else
                      Icon(
                        Icons.point_of_sale_rounded,
                        size: 20,
                        color: colors.onPrimary,
                      ),
                    const SizedBox(width: 10),
                    Text(
                      _isProcessingSale ? _t('saving') : _t('sell'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: colors.onPrimary,
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
  }

  Widget _buildDebtSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final suggestions = _customerSuggestions;
    final isDark = ThemeController.instance.isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _isProcessingSale ? null : () => _setDebtSale(!_isDebtSale),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              Checkbox(
                value: _isDebtSale,
                onChanged: _isProcessingSale
                    ? null
                    : (value) => _setDebtSale(value ?? false),
                visualDensity: VisualDensity.compact,
                fillColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return colors.primary;
                  }
                  return isDark
                      ? colors.onSurfaceVariant.withOpacity(0.15)
                      : colors.outlineVariant;
                }),
              ),
              Text(
                _t('sell_as_debt'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isDark ? colors.onSurface : colors.onSurface,
                ),
              ),
            ],
          ),
        ),
        if (_isDebtSale) ...[
          const SizedBox(height: 6),
          TextField(
            controller: _customerController,
            enabled: !_isProcessingSale,
            onChanged: _onCustomerChanged,
            style: TextStyle(
              color: isDark ? colors.onSurface : colors.onSurface,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: _t('customer_search_hint'),
              hintStyle: TextStyle(
                color: isDark
                    ? colors.onSurfaceVariant.withOpacity(0.5)
                    : colors.onSurfaceVariant,
                fontSize: 13,
              ),
              suffixIcon: IconButton(
                tooltip: _t('add_customer'),
                onPressed: _isProcessingSale ? null : _showAddCustomerDialog,
                icon: Icon(Icons.add_rounded, color: colors.primary, size: 20),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark
                      ? colors.outlineVariant.withOpacity(0.2)
                      : colors.outlineVariant,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark
                      ? colors.outlineVariant.withOpacity(0.2)
                      : colors.outlineVariant,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
              fillColor: isDark
                  ? colors.surfaceContainerHighest.withOpacity(0.1)
                  : colors.surface,
              filled: true,
            ),
          ),
          if (_selectedCustomer != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withOpacity(isDark ? 0.15 : 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _t(
                  'selected_customer',
                  args: [_customerName(_selectedCustomer!)],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: isDark ? colors.primary : colors.onPrimaryContainer,
                ),
              ),
            ),
          ] else if (_customerController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: Material(
                color: isDark
                    ? colors.surfaceContainerHighest.withOpacity(0.2)
                    : colors.surface,
                borderRadius: BorderRadius.circular(10),
                elevation: isDark ? 0 : 2,
                child: suggestions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _t('customer_not_found'),
                          style: TextStyle(
                            color: isDark
                                ? colors.onSurfaceVariant.withOpacity(0.5)
                                : colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark
                              ? colors.outlineVariant.withOpacity(0.15)
                              : colors.outlineVariant,
                        ),
                        itemBuilder: (context, index) {
                          final customer = suggestions[index];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(
                              _customerName(customer),
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? colors.onSurface
                                    : colors.onSurface,
                              ),
                            ),
                            onTap: () => _selectCustomer(customer),
                            tileColor: Colors.transparent,
                          );
                        },
                      ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  void _setDebtSale(bool value) {
    setState(() {
      _isDebtSale = value;
      if (!value) {
        _selectedCustomer = null;
        _customerController.clear();
      }
    });
    _scheduleCartSync();
  }

  Widget _summaryRow(
    BuildContext context,
    String label,
    String value, {
    bool total = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = ThemeController.instance.isDarkMode;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: total ? FontWeight.w700 : FontWeight.w500,
              fontSize: total ? 15 : 13,
              color: total
                  ? (isDark ? colors.onSurface : colors.onSurface)
                  : (isDark
                        ? colors.onSurfaceVariant.withOpacity(0.6)
                        : colors.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: total ? FontWeight.w800 : FontWeight.w600,
              color: total
                  ? colors.primary
                  : (isDark ? colors.onSurface : colors.onSurface),
              fontSize: total ? 16 : 13,
            ),
          ),
        ),
      ],
    );
  }

  String _customerName(_PosCustomer customer) =>
      customer.fullName.isEmpty ? _t('unknown_customer') : customer.fullName;

  InputDecoration _inputDecoration(
    String hint, {
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: InputBorder.none,
      filled: true,
      fillColor: Colors.transparent,
    );
  }

  String _money(num amount) => '${amount.toStringAsFixed(0)} ${_t('currency')}';
}

class _PosCustomer {
  final String id;
  final String fullName;

  const _PosCustomer({required this.id, required this.fullName});

  factory _PosCustomer.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return _PosCustomer(
      id: document.id,
      fullName: (data['fullName'] ?? data['name'] ?? '').toString(),
    );
  }
}

Future<String> _reserveSaleNumber(
  DocumentReference<Map<String, dynamic>> document,
) {
  return FirebaseFirestore.instance.runTransaction((transaction) async {
    final snapshot = await transaction.get(document);
    final rawNumber = snapshot.data()?['lastReceiptNumber'];
    final currentNumber = rawNumber is num
        ? rawNumber.toInt()
        : int.tryParse(rawNumber?.toString() ?? '') ?? 0;
    final nextNumber = currentNumber + 1;
    transaction.set(document, {
      'lastReceiptNumber': nextNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return nextNumber.toString().padLeft(6, '0');
  });
}

class ProductStockException implements Exception {
  final String code;
  final String productName;

  ProductStockException(this.code, this.productName);

  @override
  String toString() => 'ProductStockException: $code - $productName';
}

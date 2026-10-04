import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import '../utils/tenant_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:smart_store/screens/theme_controller.dart';
import '../main.dart' show SmartStoreColors;

class StockProduct {
  final String id;
  final String name;
  final String barcode;
  final num quantity;
  final String unitType;
  final num costPrice;
  final num salePrice;
  final num profit;
  final String category;
  final String status; // 'normal', 'kam', 'tugagan'
  final DateTime lastUpdate;
  final int attempts;

  StockProduct({
    required this.id,
    required this.name,
    required this.barcode,
    required this.quantity,
    required this.unitType,
    required this.costPrice,
    required this.salePrice,
    required this.profit,
    required this.category,
    required this.status,
    required this.lastUpdate,
    required this.attempts,
  });

  factory StockProduct.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    final num q = data['quantity'] as num? ?? 0;
    final String name =
        data['name']?.toString().trim() ??
        data['productName']?.toString().trim() ??
        '';
    final costPrice = (data['costPrice'] ?? data['originalPrice'] ?? 0) as num;
    final salePrice = (data['salePrice'] ?? data['sellingPrice'] ?? 0) as num;

    final String status = q == 0
        ? 'tugagan'
        : (q <= 10 ? 'kam' : (data['status']?.toString() ?? 'normal'));

    return StockProduct(
      id: doc.id,
      name: name,
      barcode: data['barcode'] ?? '',
      quantity: q,
      unitType: data['unitType'] ?? 'Dona',
      costPrice: costPrice,
      salePrice: salePrice,
      profit: salePrice - costPrice,
      category: data['category'] ?? 'Boshqa',
      status: status,
      lastUpdate: parseDate(data['lastUpdate']),
      attempts: (data['attempts'] as num? ?? 1).toInt(),
    );
  }
}

class CategoryItem {
  final String id;
  final String name;
  final Color color;
  final int order;

  CategoryItem({
    required this.id,
    required this.name,
    required this.color,
    required this.order,
  });

  factory CategoryItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final String colorHex = data['colorHex'] ?? '#8B5CF6';
    final rawOrder = data['order'];
    final int order = rawOrder is int
        ? rawOrder
        : rawOrder is num
        ? rawOrder.toInt()
        : 1 << 30;

    Color parseColor(String hex) {
      final clean = hex.replaceAll('#', '');
      final val = int.tryParse(clean, radix: 16) ?? 0xFF8B5CF6;
      return Color(val | 0xFF000000);
    }

    return CategoryItem(
      id: doc.id,
      name: data['name'] ?? '',
      color: parseColor(colorHex),
      order: order,
    );
  }
}

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _categoryScrollController = ScrollController();
  String _searchQuery = '';
  String? _selectedCategory; // null means all categories
  final Set<String> _selectedProductIds = {};

  StreamSubscription? _productsSub;
  StreamSubscription? _categoriesSub;

  List<StockProduct> _allProducts = [];
  List<CategoryItem> _allCategories = [];
  bool _isLoading = true;

  String? _draggingCategoryId;
  int? _hoveredDropIndex;
  bool _isSavingOrder = false;
  final Map<String, bool> _pressedCategories = <String, bool>{};

  // 16 preset colors for Category Creation Modal
  final List<Color> _presetColors = const [
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFF84CC16),
    Color(0xFFF97316),
    Color(0xFFD946EF),
    Color(0xFF64748B),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF43F5E),
  ];

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    _subscribeToCategories();
    _subscribeToProducts();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    _productsSub?.cancel();
    _categoriesSub?.cancel();
    _searchController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  void _subscribeToCategories() {
    _categoriesSub = TenantFirestore.categories.snapshots().listen((snapshot) {
      final list = snapshot.docs
          .map((doc) => CategoryItem.fromFirestore(doc))
          .toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      if (mounted) {
        setState(() {
          _allCategories = list;
        });
      }
    });
  }

  void _subscribeToProducts() {
    _productsSub = TenantFirestore.products.snapshots().listen(
      (snapshot) {
        final list = snapshot.docs
            .map((doc) => StockProduct.fromFirestore(doc))
            .toList();
        if (mounted) {
          setState(() {
            _allProducts = list;
            _isLoading = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  String _tr(String key, String fallback, [List<String>? args]) {
    String text = key.tr();
    if (text == key) text = fallback;
    if (args != null) {
      for (int i = 0; i < args.length; i++) {
        text = text.replaceFirst('{$i}', args[i]);
      }
    }
    return text;
  }

  String _formatCurrency(num value) {
    final String str = value.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(' ');
      }
      buffer.write(str[i]);
    }
    return '${buffer.toString()} UZS';
  }

  String _formatCurrencySigned(num value) {
    final String str = value.abs().toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(' ');
      }
      buffer.write(str[i]);
    }
    final sign = value > 0 ? '+' : (value < 0 ? '-' : '');
    return '$sign${buffer.toString()} UZS';
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('dd/MM/yy, HH:mm').format(dt);
  }

  List<StockProduct> get _filteredProducts {
    return _allProducts.where((p) {
      final matchesSearch =
          p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.barcode.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesCategory =
          _selectedCategory == null ||
          p.category.toLowerCase() == _selectedCategory!.toLowerCase();

      return matchesSearch && matchesCategory;
    }).toList();
  }

  int _getCategoryProductCount(String categoryName) {
    return _allProducts
        .where((p) => p.category.toLowerCase() == categoryName.toLowerCase())
        .length;
  }

  Future<void> _deleteSelectedProducts() async {
    final count = _selectedProductIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final isDark = ThemeController.instance.isDarkMode;
        final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
        final borderColor = isDark
            ? SmartStoreColors.darkDivider
            : const Color(0xFFE2E8F0);

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: SmartStoreColors.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: SmartStoreColors.danger,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _tr('stock_page.delete_confirm_title', 'Delete product?'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? SmartStoreColors.darkTextPrimary
                        : SmartStoreColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _tr(
                    'stock_page.delete_confirm_content',
                    'Do you want to delete the selected product(s)?',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? SmartStoreColors.darkTextSecondary
                        : SmartStoreColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _tr('stock_page.delete_confirm_cancel', 'Cancel'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SmartStoreColors.danger,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _tr('stock_page.delete_confirm_delete', 'Delete'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    String username = 'Unknown';
    try {
      final profile = await TenantFirestore.userDocument.get();
      username = (profile.data()?['username'] ?? 'Unknown').toString();
    } catch (_) {}

    final batch = FirebaseFirestore.instance.batch();
    for (final id in _selectedProductIds) {
      final docSnap = await TenantFirestore.products.doc(id).get();
      if (docSnap.exists) {
        final data = docSnap.data() ?? {};
        final q = (data['quantity'] as num?) ?? 0;
        final cost = (data['costPrice'] ?? data['originalPrice'] ?? 0) as num;
        final name = (data['name'] ?? data['productName'] ?? '').toString();
        if (q > 0) {
          final entryRef = TenantFirestore.inventoryEntries.doc();
          batch.set(entryRef, {
            'type': 'adjustment_outgoing',
            'productId': id,
            'productName': name,
            'quantity': q,
            'originalPrice': cost,
            'sellingPrice': 0,
            'totalCostValue': (q * cost).toDouble(),
            'totalSaleValue': 0,
            'totalProfit': 0,
            'user': username,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
        batch.delete(docSnap.reference);
      }
    }
    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'stock_page.delete_success',
              'Deleted successfully',
            ).replaceFirst('{0}', '$count'),
          ),
          backgroundColor: SmartStoreColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
    setState(() {
      _selectedProductIds.clear();
    });
  }

  void _showEditProductModal(StockProduct product) {
    final miqdorCtrl = TextEditingController(text: product.quantity.toString());
    final aslNarxCtrl = TextEditingController(
      text: product.costPrice.toString(),
    );
    final sotishNarxCtrl = TextEditingController(
      text: product.salePrice.toString(),
    );

    showDialog(
      context: context,
      builder: (context) {
        final isDark = ThemeController.instance.isDarkMode;
        final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
        final borderColor = isDark
            ? SmartStoreColors.darkDivider
            : const Color(0xFFE2E8F0);
        final inputBg = isDark
            ? SmartStoreColors.darkBackground
            : const Color(0xFFF8FAFC);

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: cardBg,
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _tr(
                              'stock_page.edit_product',
                              'Mahsulotni tahrirlash: ',
                            ) +
                            product.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? SmartStoreColors.darkTextPrimary
                              : SmartStoreColors.lightTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: isDark
                            ? SmartStoreColors.darkTextMuted
                            : SmartStoreColors.lightTextMuted,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Miqdor
                Text(
                  _tr('stock_page.col_quantity', 'Miqdori'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? SmartStoreColors.darkTextPrimary
                        : SmartStoreColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: miqdorCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: inputBg,
                    hintText: product.quantity.toString(),
                    hintStyle: TextStyle(
                      color: isDark
                          ? SmartStoreColors.darkTextMuted
                          : SmartStoreColors.lightTextMuted,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: SmartStoreColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Asl narx
                Text(
                  _tr('stock_page.col_cost_price', 'Asl narx'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? SmartStoreColors.darkTextPrimary
                        : SmartStoreColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: aslNarxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: inputBg,
                    hintText: product.costPrice.toString(),
                    hintStyle: TextStyle(
                      color: isDark
                          ? SmartStoreColors.darkTextMuted
                          : SmartStoreColors.lightTextMuted,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: SmartStoreColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Sotish narx
                Text(
                  _tr('stock_page.col_sale_price', 'Sotish narx'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? SmartStoreColors.darkTextPrimary
                        : SmartStoreColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: sotishNarxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: inputBg,
                    hintText: product.salePrice.toString(),
                    hintStyle: TextStyle(
                      color: isDark
                          ? SmartStoreColors.darkTextMuted
                          : SmartStoreColors.lightTextMuted,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: SmartStoreColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        _tr('customers.cancel', 'Bekor qilish'),
                        style: TextStyle(
                          color: isDark
                              ? SmartStoreColors.darkTextMuted
                              : SmartStoreColors.lightTextMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        final newQ =
                            int.tryParse(miqdorCtrl.text) ??
                            product.quantity.toInt();
                        final cost =
                            num.tryParse(aslNarxCtrl.text) ?? product.costPrice;
                        final sale =
                            num.tryParse(sotishNarxCtrl.text) ??
                            product.salePrice;
                        final profit = sale - cost;

                        // Status qayta hisoblash
                        String newStatus = 'normal';
                        if (newQ == 0) {
                          newStatus = 'tugagan';
                        } else if (newQ <= 10) {
                          newStatus = 'kam';
                        }

                        // Mahsulotni yangilash
                        await TenantFirestore.products.doc(product.id).update({
                          'quantity': newQ,
                          'costPrice': cost,
                          'originalPrice': cost,
                          'salePrice': sale,
                          'sellingPrice': sale,
                          'profit': profit,
                          'status': newStatus,
                          'lastUpdate': FieldValue.serverTimestamp(),
                        });

                        // Agar miqdor ko'paygan bo'lsa — yangi kirim yozuvi qo'shish
                        final addedQty = newQ - product.quantity.toInt();
                        if (addedQty > 0) {
                          String username = 'Unknown';
                          try {
                            final profile = await TenantFirestore.userDocument
                                .get();
                            username =
                                (profile.data()?['username'] ?? 'Unknown')
                                    .toString();
                          } catch (_) {}

                          await TenantFirestore.inventoryEntries.add({
                            'type': 'incoming',
                            'productId': product.id,
                            'productName': product.name,
                            'quantity': addedQty,
                            'originalPrice': cost,
                            'sellingPrice': sale,
                            'totalValue': (addedQty * cost).toDouble(),
                            'profitPerUnit': (sale - cost).toDouble(),
                            'user': username,
                            'timestamp': FieldValue.serverTimestamp(),
                          });
                        } else if (addedQty < 0) {
                          String username = 'Unknown';
                          try {
                            final profile = await TenantFirestore.userDocument
                                .get();
                            username =
                                (profile.data()?['username'] ?? 'Unknown')
                                    .toString();
                          } catch (_) {}

                          final removedQty = addedQty.abs();
                          await TenantFirestore.inventoryEntries.add({
                            'type': 'adjustment_outgoing',
                            'productId': product.id,
                            'productName': product.name,
                            'quantity': removedQty,
                            'originalPrice': cost,
                            'sellingPrice': 0,
                            'totalCostValue': (removedQty * cost).toDouble(),
                            'totalSaleValue': 0,
                            'totalProfit': 0,
                            'user': username,
                            'timestamp': FieldValue.serverTimestamp(),
                          });
                        }

                        if (context.mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(120, 44),
                        backgroundColor: SmartStoreColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _tr('stock_page.update', 'Yangilash'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteCategory(CategoryItem category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final isDark = ThemeController.instance.isDarkMode;
        final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
        final borderColor = isDark
            ? SmartStoreColors.darkDivider
            : const Color(0xFFE2E8F0);
        final affectedCount = _getCategoryProductCount(category.name);

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: SmartStoreColors.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: SmartStoreColors.danger,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _tr(
                    'stock_page.category_delete_confirm_title',
                    'Kategoriyani o\'chirish?',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? SmartStoreColors.darkTextPrimary
                        : SmartStoreColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  affectedCount > 0
                      ? _tr(
                          'stock_page.category_delete_confirm_content_with_products',
                          '"{0}" kategoriyasi o\'chiriladi. Unga tegishli {1} ta mahsulot o\'chirilmaydi, faqat kategoriyasiz qoladi.',
                          [(category.name), '$affectedCount'],
                        )
                      : _tr(
                          'stock_page.category_delete_confirm_content',
                          '"{0}" kategoriyasini o\'chirmoqchimisiz?',
                          [(category.name)],
                        ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? SmartStoreColors.darkTextSecondary
                        : SmartStoreColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _tr(
                            'stock_page.delete_confirm_cancel',
                            'Bekor qilish',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SmartStoreColors.danger,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _tr('stock_page.delete_confirm_delete', 'O\'chirish'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    // Ushbu kategoriyaga tegishli mahsulotlarni O'CHIRMAYMIZ,
    // faqat categoriyasini bo'shatamiz (kategoriyasiz qoladi)
    final batch = FirebaseFirestore.instance.batch();
    final affectedProducts = _allProducts
        .where((p) => p.category.toLowerCase() == category.name.toLowerCase())
        .toList();

    for (final p in affectedProducts) {
      final ref = TenantFirestore.products.doc(p.id);
      batch.update(ref, {'category': ''});
    }

    final categoryRef = TenantFirestore.categories.doc(category.id);
    batch.delete(categoryRef);

    await batch.commit();

    if (mounted) {
      if (_selectedCategory == category.name) {
        setState(() => _selectedCategory = null);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr('stock_page.category_delete_success', 'Kategoriya o\'chirildi'),
          ),
          backgroundColor: SmartStoreColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _reorderCategories(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (_isSavingOrder) return;
    if (oldIndex < 0 || oldIndex >= _allCategories.length) return;
    if (newIndex < 0 || newIndex >= _allCategories.length) return;

    _isSavingOrder = true;
    try {
      final reordered = List<CategoryItem>.from(_allCategories);
      final item = reordered.removeAt(oldIndex);
      reordered.insert(newIndex, item);

      final batch = FirebaseFirestore.instance.batch();
      for (int i = 0; i < reordered.length; i++) {
        final cat = reordered[i];
        final ref = TenantFirestore.categories.doc(cat.id);
        batch.set(ref, {'order': i}, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isSavingOrder = false;
          _draggingCategoryId = null;
          _hoveredDropIndex = null;
        });
      }
    }
  }

  void _showCategoryActionsMenu(
    BuildContext anchorContext,
    CategoryItem category,
  ) {
    final isDark = ThemeController.instance.isDarkMode;
    final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
    final borderColor = isDark
        ? SmartStoreColors.darkDivider
        : const Color(0xFFE2E8F0);

    final RenderBox button = anchorContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: anchorContext,
      position: position,
      color: cardBg,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor),
      ),
      constraints: const BoxConstraints(minWidth: 170),
      items: [
        PopupMenuItem<String>(
          value: 'edit',
          height: 44,
          child: Row(
            children: [
              Icon(
                Icons.edit_outlined,
                size: 18,
                color: isDark
                    ? SmartStoreColors.darkTextPrimary
                    : SmartStoreColors.lightTextPrimary,
              ),
              const SizedBox(width: 10),
              Text(
                _tr('stock_page.category_action_edit', 'Tahrirlash'),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? SmartStoreColors.darkTextPrimary
                      : SmartStoreColors.lightTextPrimary,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 44,
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: SmartStoreColors.danger,
              ),
              const SizedBox(width: 10),
              Text(
                _tr('stock_page.category_action_delete', 'O\'chirish'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: SmartStoreColors.danger,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'edit') {
        _showEditCategoryModal(category);
      } else if (value == 'delete') {
        _deleteCategory(category);
      }
    });
  }

  void _showEditCategoryModal(CategoryItem category) {
    final nameController = TextEditingController(text: category.name);
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = ThemeController.instance.isDarkMode;
            final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
            final borderColor = isDark
                ? SmartStoreColors.darkDivider
                : const Color(0xFFE2E8F0);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.4 : 0.10),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Header: icon + title + close ──
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: category.color.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.edit_rounded,
                              color: category.color,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _tr(
                                    'stock_page.category_edit_title',
                                    'Kategoriyani tahrirlash',
                                  ),
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? SmartStoreColors.darkTextPrimary
                                        : SmartStoreColors.lightTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  category.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? SmartStoreColors.darkTextMuted
                                        : SmartStoreColors.lightTextMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Navigator.pop(dialogContext),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: isDark
                                    ? SmartStoreColors.darkTextMuted
                                    : SmartStoreColors.lightTextMuted,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 22),

                      // ── Input label ──
                      Text(
                        _tr('stock_page.category_edit_name', 'Yangi nom'),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? SmartStoreColors.darkTextSecondary
                              : SmartStoreColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── Input field ──
                      TextFormField(
                        controller: nameController,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? SmartStoreColors.darkTextPrimary
                              : SmartStoreColors.lightTextPrimary,
                        ),
                        validator: (val) {
                          final name = (val ?? '').trim();
                          if (name.isEmpty) {
                            return _tr(
                              'stock_page.category_name_required',
                              'Kategoriya nomi bo\'sh bo\'lishi mumkin emas',
                            );
                          }
                          if (name.toLowerCase() !=
                              category.name.toLowerCase()) {
                            final exists = _allCategories.any(
                              (c) =>
                                  c.id != category.id &&
                                  c.name.toLowerCase() == name.toLowerCase(),
                            );
                            if (exists) {
                              return _tr(
                                'stock_page.category_already_exists',
                                'Bu kategoriya allaqachon mavjud',
                              );
                            }
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: _tr(
                            'stock_page.category_edit_hint',
                            'Kategoriya nomini kiriting',
                          ),
                          hintStyle: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? SmartStoreColors.darkTextMuted
                                : SmartStoreColors.lightTextMuted,
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: category.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? SmartStoreColors.darkBackground
                              : const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: SmartStoreColors.primary,
                              width: 1.6,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: SmartStoreColors.danger,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 26),

                      // ── Actions: Cancel | Update ──
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: OutlinedButton(
                                onPressed: isSaving
                                    ? null
                                    : () => Navigator.pop(dialogContext),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isDark
                                      ? SmartStoreColors.darkTextSecondary
                                      : SmartStoreColors.lightTextSecondary,
                                  side: BorderSide(color: borderColor),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  _tr(
                                    'stock_page.category_edit_cancel',
                                    'Bekor qilish',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: ElevatedButton(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        if (!formKey.currentState!.validate()) {
                                          return;
                                        }
                                        final newName = nameController.text
                                            .trim();
                                        if (newName.toLowerCase() ==
                                            category.name.toLowerCase()) {
                                          Navigator.pop(dialogContext);
                                          return;
                                        }

                                        final normalized = newName
                                            .toLowerCase();
                                        final duplicate = _allCategories.any(
                                          (c) =>
                                              c.id != category.id &&
                                              c.name.toLowerCase() ==
                                                  normalized,
                                        );
                                        if (duplicate) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  _tr(
                                                    'stock_page.category_already_exists',
                                                    'Bu kategoriya allaqachon mavjud',
                                                  ),
                                                ),
                                                backgroundColor:
                                                    SmartStoreColors.danger,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                            );
                                          }
                                          return;
                                        }

                                        setModalState(() => isSaving = true);

                                        try {
                                          await TenantFirestore.categories
                                              .doc(category.id)
                                              .update({'name': newName});
                                          if (dialogContext.mounted) {
                                            Navigator.pop(dialogContext);
                                          }
                                        } catch (_) {
                                          setModalState(() => isSaving = false);
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SmartStoreColors.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: SmartStoreColors
                                      .primary
                                      .withOpacity(0.6),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: isSaving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          valueColor: AlwaysStoppedAnimation(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        _tr(
                                          'stock_page.category_edit_update',
                                          'Yangilash',
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddCategoryModal() {
    final nameController = TextEditingController();
    Color selectedColor = _presetColors.first;
    final formKey = GlobalKey<FormState>();
    String? formError;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = ThemeController.instance.isDarkMode;
            final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
            final borderColor = isDark
                ? SmartStoreColors.darkDivider
                : const Color(0xFFE2E8F0);

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: cardBg,
              child: Container(
                width: 440,
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            _tr(
                              'stock_page.add_category_title',
                              'Yangi kategoriya qo\'shish',
                            ),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? SmartStoreColors.darkTextPrimary
                                  : SmartStoreColors.lightTextPrimary,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Kategoriya nomi
                      Text(
                        _tr('stock_page.category_name', 'Kategoriya nomi'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? SmartStoreColors.darkTextPrimary
                              : SmartStoreColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: nameController,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? SmartStoreColors.darkTextPrimary
                              : SmartStoreColors.lightTextPrimary,
                        ),
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        validator: (val) {
                          final name = (val ?? '').trim();
                          if (name.isEmpty) {
                            return _tr(
                              'stock_page.category_name_required',
                              'Kategoriya nomi bo\'sh bo\'lishi mumkin emas',
                            );
                          }
                          final exists = _allCategories.any(
                            (c) => c.name.toLowerCase() == name.toLowerCase(),
                          );
                          if (exists) {
                            return _tr(
                              'stock_page.category_already_exists',
                              'Bu kategoriya allaqachon mavjud',
                            );
                          }
                          return null;
                        },
                        onChanged: (_) {
                          if (formError != null) {
                            setModalState(() => formError = null);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: _tr(
                            'stock_page.category_name_hint',
                            'Kategoriya nomini kiriting',
                          ),
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? SmartStoreColors.darkTextMuted
                                : SmartStoreColors.lightTextMuted,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? SmartStoreColors.darkBackground
                              : const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: SmartStoreColors.danger,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: SmartStoreColors.danger,
                              width: 1.6,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: SmartStoreColors.primary,
                              width: 1.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 16 Preset Colors Grid
                      Text(
                        _tr('stock_page.select_color', 'Rang tanlang'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? SmartStoreColors.darkTextPrimary
                              : SmartStoreColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _presetColors.map((color) {
                          final isSelected = selectedColor == color;
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                selectedColor = color;
                              });
                            },
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                        width: 3,
                                      )
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withOpacity(0.4),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              _tr('customers.cancel', 'Bekor qilish'),
                              style: TextStyle(
                                color: isDark
                                    ? SmartStoreColors.darkTextMuted
                                    : SmartStoreColors.lightTextMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 42,
                            child: ElevatedButton(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                final name = nameController.text.trim();
                                final normalized = name.toLowerCase();

                                final duplicate = _allCategories.any(
                                  (c) => c.name.toLowerCase() == normalized,
                                );
                                if (duplicate) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _tr(
                                            'stock_page.category_already_exists',
                                            'Bu kategoriya allaqachon mavjud',
                                          ),
                                        ),
                                        backgroundColor:
                                            SmartStoreColors.danger,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                final colorHex =
                                    '#${selectedColor.value.toRadixString(16).substring(2)}';
                                final navigator = Navigator.of(context);
                                final int newOrder = _allCategories.isEmpty
                                    ? 0
                                    : _allCategories
                                              .map((e) => e.order)
                                              .reduce((a, b) => a > b ? a : b) +
                                          1;

                                await TenantFirestore.categories.add({
                                  'name': name,
                                  'colorHex': colorHex,
                                  'order': newOrder,
                                  'createdAt': FieldValue.serverTimestamp(),
                                });

                                navigator.pop();
                              },
                              style: ElevatedButton.styleFrom(
                                minimumSize: Size.zero,
                                backgroundColor: SmartStoreColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                _tr('customers.add_button', 'Qo\'shish'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final _ = context.locale; // Subscribe to EasyLocalization locale changes
    final isDark = ThemeController.instance.isDarkMode;

    final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
    final borderColor = isDark
        ? SmartStoreColors.darkDivider
        : const Color(0xFFE2E8F0);

    final products = _filteredProducts;
    final activeCategoryName =
        _selectedCategory ??
        _tr('stock_page.all_categories', 'Barcha kategoriyalar');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Search Header ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr('stock_page.title', 'Ombor'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? SmartStoreColors.darkTextPrimary
                              : SmartStoreColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _tr(
                          'stock_page.subtitle',
                          'Mahsulotlar va zaxirani boshqaring',
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? SmartStoreColors.darkTextMuted
                              : SmartStoreColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Delete Button (if selected)
                if (_selectedProductIds.isNotEmpty) ...[
                  SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _deleteSelectedProducts,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      label: Text(
                        '${_tr('stock_page.delete', 'O\'chirish')} (${_selectedProductIds.length})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // Search Input Field
                SizedBox(
                  width: 320,
                  height: 44,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? SmartStoreColors.darkTextPrimary
                          : SmartStoreColors.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: _tr('stock_page.search_hint', 'Qidirish...'),
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? SmartStoreColors.darkTextMuted
                            : SmartStoreColors.lightTextMuted,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: isDark
                            ? SmartStoreColors.darkTextMuted
                            : SmartStoreColors.lightTextMuted,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? SmartStoreColors.darkBackground
                          : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Categories Card ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Section Header
                  Row(
                    children: [
                      Text(
                        _tr('stock_page.categories', 'Kategoriyalar'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? SmartStoreColors.darkTextPrimary
                              : SmartStoreColors.lightTextPrimary,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 38,
                        child: OutlinedButton.icon(
                          onPressed: _showAddCategoryModal,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? SmartStoreColors.darkTextPrimary
                                : SmartStoreColors.lightTextPrimary,
                            side: BorderSide(color: borderColor),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                            _tr(
                              'stock_page.add_category',
                              '+ Kategoriya qo\'shish',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Horizontal Category Cards Row — nom uzunligiga moslashadi,
                  // 3 nuqta tugmasi kartaning ICHIDA joylashgan
                  Listener(
                    onPointerSignal: (signal) {
                      if (signal is PointerScrollEvent) {
                        final dy = signal.scrollDelta.dy;
                        if (dy.abs() < 0.5) return;
                        final pos = _categoryScrollController.position;
                        final current = pos.pixels;
                        final maxExtent = pos.maxScrollExtent;
                        final minExtent = pos.minScrollExtent;
                        if (maxExtent <= minExtent) return;
                        final next = (current + dy).clamp(minExtent, maxExtent);
                        if (next != current) {
                          _categoryScrollController.jumpTo(next);
                        }
                      }
                    },
                    child: SingleChildScrollView(
                      controller: _categoryScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Row(
                        children: _allCategories.asMap().entries.map((entry) {
                          final index = entry.key;
                          final cat = entry.value;
                          final count = _getCategoryProductCount(cat.name);
                          final isSelected = _selectedCategory == cat.name;
                          final bool isDragging = _draggingCategoryId == cat.id;
                          final bool isHoveredDrop = _hoveredDropIndex == index;
                          final bool isPressed =
                              _pressedCategories[cat.id] ?? false;

                          Widget buildCard({
                            required bool forFeedback,
                            required double scale,
                            required double opacity,
                            required bool showShadow,
                            required bool showDropHighlight,
                            MouseCursor? cursor,
                          }) {
                            return AnimatedScale(
                              scale: scale,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              child: AnimatedOpacity(
                                opacity: opacity,
                                duration: const Duration(milliseconds: 180),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  constraints: const BoxConstraints(
                                    minWidth: 150,
                                    maxWidth: 260,
                                  ),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    14,
                                    8,
                                    14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cat.color.withOpacity(
                                      isSelected ? 0.18 : 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: showDropHighlight
                                          ? cat.color.withOpacity(0.9)
                                          : (isSelected
                                                ? cat.color
                                                : cat.color.withOpacity(0.4)),
                                      width: showDropHighlight
                                          ? 2.5
                                          : (isSelected ? 2 : 1),
                                    ),
                                    boxShadow: [
                                      if (showDropHighlight)
                                        BoxShadow(
                                          color: cat.color.withOpacity(0.28),
                                          blurRadius: 18,
                                          spreadRadius: 2,
                                          offset: const Offset(0, 6),
                                        ),
                                      if (showShadow)
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.18),
                                          blurRadius: 22,
                                          spreadRadius: 2,
                                          offset: const Offset(0, 10),
                                        ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              cat.name,
                                              softWrap: true,
                                              maxLines: 2,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                height: 1.2,
                                                color: isDark
                                                    ? SmartStoreColors
                                                          .darkTextPrimary
                                                    : SmartStoreColors
                                                          .lightTextPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _tr(
                                                'stock_page.items_count',
                                                '{0} mahsulot',
                                                ['$count'],
                                              ),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? SmartStoreColors
                                                          .darkTextMuted
                                                    : SmartStoreColors
                                                          .lightTextMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Builder(
                                        builder: (menuContext) {
                                          return SizedBox(
                                            width: 32,
                                            height: 32,
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              tooltip: _tr(
                                                'stock_page.category_actions',
                                                'Amallar',
                                              ),
                                              icon: Icon(
                                                Icons.more_horiz_rounded,
                                                size: 18,
                                                color: isDark
                                                    ? SmartStoreColors
                                                          .darkTextSecondary
                                                    : SmartStoreColors
                                                          .lightTextSecondary,
                                              ),
                                              onPressed: () =>
                                                  _showCategoryActionsMenu(
                                                    menuContext,
                                                    cat,
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          final cardForFeedback = Material(
                            color: Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: IntrinsicWidth(
                                child: buildCard(
                                  forFeedback: true,
                                  scale: 1.04,
                                  opacity: 1.0,
                                  showShadow: true,
                                  showDropHighlight: false,
                                ),
                              ),
                            ),
                          );

                          return DragTarget<int>(
                            onWillAcceptWithDetails: (details) {
                              final draggedIndex = details.data;
                              if (draggedIndex == index) return false;
                              setState(() => _hoveredDropIndex = index);
                              return true;
                            },
                            onLeave: (data) {
                              if (_hoveredDropIndex == index) {
                                setState(() => _hoveredDropIndex = null);
                              }
                            },
                            onAcceptWithDetails: (details) {
                              final fromIndex = details.data;
                              setState(() => _hoveredDropIndex = null);
                              _reorderCategories(fromIndex, index);
                            },
                            builder: (context, candidateData, rejectedData) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Listener(
                                  onPointerDown: (_) {
                                    setState(() {
                                      _pressedCategories[cat.id] = true;
                                    });
                                  },
                                  onPointerUp: (_) {
                                    setState(() {
                                      _pressedCategories[cat.id] = false;
                                    });
                                  },
                                  onPointerCancel: (_) {
                                    setState(() {
                                      _pressedCategories[cat.id] = false;
                                    });
                                  },
                                  child: Draggable<int>(
                                    data: index,
                                    maxSimultaneousDrags: 1,
                                    dragAnchorStrategy:
                                        pointerDragAnchorStrategy,
                                    feedback: cardForFeedback,
                                    childWhenDragging: IntrinsicWidth(
                                      child: buildCard(
                                        forFeedback: false,
                                        scale: 0.985,
                                        opacity: 0.45,
                                        showShadow: false,
                                        showDropHighlight: false,
                                      ),
                                    ),
                                    onDragStarted: () {
                                      setState(() {
                                        _draggingCategoryId = cat.id;
                                        _hoveredDropIndex = index;
                                      });
                                    },
                                    onDragEnd: (details) {
                                      setState(() {
                                        if (_draggingCategoryId == cat.id) {
                                          _draggingCategoryId = null;
                                        }
                                        _hoveredDropIndex = null;
                                      });
                                    },
                                    child: MouseRegion(
                                      cursor: isDragging
                                          ? SystemMouseCursors.grabbing
                                          : (isPressed
                                                ? SystemMouseCursors.grabbing
                                                : SystemMouseCursors.grab),
                                      child: IntrinsicWidth(
                                        child: InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (_selectedCategory ==
                                                  cat.name) {
                                                _selectedCategory = null;
                                              } else {
                                                _selectedCategory = cat.name;
                                              }
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: buildCard(
                                            forFeedback: false,
                                            scale: isDragging
                                                ? 0.985
                                                : (isPressed ? 1.015 : 1.0),
                                            opacity: 1.0,
                                            showShadow: false,
                                            showDropHighlight:
                                                isHoveredDrop && !isDragging,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Products Table Card ──
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Table Title Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Text(
                          '$activeCategoryName (${products.length})',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? SmartStoreColors.darkTextPrimary
                                : SmartStoreColors.lightTextPrimary,
                          ),
                        ),
                        if (_selectedCategory != null) ...[
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: () =>
                                setState(() => _selectedCategory = null),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: SmartStoreColors.primary.withOpacity(
                                  0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _tr(
                                      'stock_page.all_categories',
                                      'Barcha kategoriyalar',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: SmartStoreColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: SmartStoreColors.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Table Header (NO Image column!)
                  Container(
                    color: isDark
                        ? SmartStoreColors.darkBackground
                        : const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // Checkbox for all
                        SizedBox(
                          width: 40,
                          child: Checkbox(
                            value:
                                products.isNotEmpty &&
                                _selectedProductIds.length == products.length,
                            activeColor: SmartStoreColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedProductIds.addAll(
                                    products.map((p) => p.id),
                                  );
                                } else {
                                  _selectedProductIds.clear();
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Nom Column
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('stock_page.col_name', 'Nom'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Shtrix code Column
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('stock_page.col_barcode', 'Shtrix code'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Miqdori Column
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('stock_page.col_quantity', 'Miqdori'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Asl narx Column
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('stock_page.col_cost_price', 'Asl narx'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Sotish narx Column
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('stock_page.col_sale_price', 'Sotish narx'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Foyda Column
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('stock_page.col_profit', 'Foyda'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Holat Column
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('stock_page.col_status', 'Holat'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Last update Column
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('stock_page.col_last_update', 'Last update'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Attempts Column
                        Expanded(
                          flex: 1,
                          child: Text(
                            _tr('stock_page.col_attempts', 'Attempts'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        const SizedBox(width: 36),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Table Body
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (products.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 44,
                              color: isDark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _tr(
                                'stock_page.no_products',
                                'Mahsulotlar topilmadi',
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? SmartStoreColors.darkTextMuted
                                    : SmartStoreColors.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: products.length,
                      separatorBuilder: (_, index) => Divider(
                        height: 1,
                        color: borderColor.withOpacity(0.5),
                      ),
                      itemBuilder: (context, index) {
                        final p = products[index];

                        // Quantity Color Rules:
                        // 0 ta -> RED
                        // 1-10 ta -> YELLOW/ORANGE
                        // 10+ ta -> GREEN
                        Color qtyColor = const Color(0xFF10B981);
                        Color statusBg = const Color(
                          0xFF10B981,
                        ).withOpacity(0.12);
                        String statusLabel = _tr(
                          'stock_page.status_normal',
                          'Normal',
                        );

                        if (p.quantity == 0) {
                          qtyColor = const Color(0xFFEF4444);
                          statusBg = const Color(0xFFEF4444).withOpacity(0.12);
                          statusLabel = _tr(
                            'stock_page.status_out_of_stock',
                            'Tugagan',
                          );
                        } else if (p.quantity <= 10) {
                          qtyColor = const Color(0xFFF59E0B);
                          statusBg = const Color(0xFFF59E0B).withOpacity(0.12);
                          statusLabel = _tr(
                            'stock_page.status_low_stock',
                            'Kam',
                          );
                        }

                        // Zarar (profit < 0) bo'lgan mahsulot uchun QIZIL rang sozlamalari
                        final num totalProfit = p.quantity * p.profit;
                        final bool isLoss = totalProfit < 0;
                        final Color profitTextColor = totalProfit >= 0
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444);
                        final Color? rowBgColor = isLoss
                            ? (isDark
                                  ? const Color(0xFF3B1414)
                                  : const Color(0xFFFEF2F2))
                            : null;
                        final Color? rowBorderColor = isLoss
                            ? (isDark
                                  ? const Color(0xFF7F1D1D).withOpacity(0.6)
                                  : const Color(0xFFFECACA).withOpacity(0.9))
                            : null;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: rowBgColor,
                            border: isLoss
                                ? Border(
                                    left: BorderSide(
                                      color: rowBorderColor!,
                                      width: 3,
                                    ),
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              // Row Checkbox
                              SizedBox(
                                width: 40,
                                child: Checkbox(
                                  value: _selectedProductIds.contains(p.id),
                                  activeColor: SmartStoreColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedProductIds.add(p.id);
                                      } else {
                                        _selectedProductIds.remove(p.id);
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Nom Column
                              Expanded(
                                flex: 2,
                                child: Text(
                                  p.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? SmartStoreColors.darkTextPrimary
                                        : SmartStoreColors.lightTextPrimary,
                                  ),
                                ),
                              ),

                              // Shtrix code Column
                              Expanded(
                                flex: 2,
                                child: Text(
                                  p.barcode.isEmpty ? '—' : p.barcode,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? SmartStoreColors.darkTextMuted
                                        : SmartStoreColors.lightTextMuted,
                                  ),
                                ),
                              ),

                              // Miqdori Column (Colored according to stock level)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${p.quantity} ${p.unitType}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: qtyColor,
                                  ),
                                ),
                              ),

                              // Asl narx Column
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatCurrency(p.costPrice),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? SmartStoreColors.darkTextPrimary
                                        : SmartStoreColors.lightTextPrimary,
                                  ),
                                ),
                              ),

                              // Sotish narx Column
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatCurrency(p.salePrice),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? SmartStoreColors.darkTextPrimary
                                        : SmartStoreColors.lightTextPrimary,
                                  ),
                                ),
                              ),

                              // Foyda Column (Yashil = foyda, Qizil = zarar)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatCurrencySigned(totalProfit),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: profitTextColor,
                                  ),
                                ),
                              ),

                              // Holat Column (Badge)
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusBg,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: qtyColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Last update Column
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatDateTime(p.lastUpdate),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? SmartStoreColors.darkTextMuted
                                        : SmartStoreColors.lightTextMuted,
                                  ),
                                ),
                              ),

                              // Attempts Column
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '-',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? SmartStoreColors.darkTextPrimary
                                        : SmartStoreColors.lightTextPrimary,
                                  ),
                                ),
                              ),

                              // Amallar — popup menu
                              SizedBox(
                                width: 36,
                                child: PopupMenuButton<String>(
                                  icon: Icon(
                                    Icons.more_vert_rounded,
                                    size: 18,
                                    color: isDark
                                        ? SmartStoreColors.darkTextSecondary
                                        : SmartStoreColors.lightTextSecondary,
                                  ),
                                  color: isDark
                                      ? SmartStoreColors.darkSurface
                                      : Colors.white,
                                  elevation: 8,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isDark
                                          ? SmartStoreColors.darkDivider
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem<String>(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.edit_rounded,
                                            size: 16,
                                            color: Color(0xFF3B82F6),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _tr(
                                              'stock_page.edit',
                                              'Tahrirlash',
                                            ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? SmartStoreColors
                                                        .darkTextPrimary
                                                  : SmartStoreColors
                                                        .lightTextPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 16,
                                            color: Color(0xFFEF4444),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _tr(
                                              'stock_page.delete_product',
                                              'O\'chirish',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFEF4444),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _showEditProductModal(p);
                                    } else if (value == 'delete') {
                                      setState(() {
                                        _selectedProductIds.add(p.id);
                                      });
                                      _deleteSelectedProducts();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

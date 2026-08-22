import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/tenant_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_store/screens/theme_controller.dart';
import '../main.dart' show SmartStoreColors;


class AddingPage extends StatefulWidget {
  const AddingPage({super.key});

  @override
  State<AddingPage> createState() => _AddingPageState();
}

class _AddingPageState extends State<AddingPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _costPriceController = TextEditingController();
  final TextEditingController _salePriceController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();

  String _selectedType = 'Dona';
  String? _selectedCategory;

  num _profitPerUnit = 0;
  bool _isSubmitting = false;
  String? _editingDraftId; // null = yangi qo'shish, non-null = tahrirlash rejimi
  bool _suppressBarcodeLookup = false;
  Timer? _barcodeDebounceTimer;

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    _costPriceController.addListener(_calculateProfit);
    _salePriceController.addListener(_calculateProfit);
    _barcodeController.addListener(_onBarcodeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    _barcodeDebounceTimer?.cancel();
    _barcodeController.removeListener(_onBarcodeChanged);
    _nameController.dispose();
    _quantityController.dispose();
    _costPriceController.dispose();
    _salePriceController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  void _onBarcodeChanged() {
    if (_suppressBarcodeLookup) return;
    if (_editingDraftId != null) return;

    final barcode = _barcodeController.text.trim();
    _barcodeDebounceTimer?.cancel();
    _barcodeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (barcode.isEmpty) return;
      _lookupAndFillByBarcode(barcode);
    });
  }

  Future<void> _lookupAndFillByBarcode(String barcode) async {
    try {
      final snapshot = await TenantFirestore.products
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();
      if (!mounted) return;
      if (snapshot.docs.isEmpty) return;

      final doc = snapshot.docs.first;
      final data = doc.data();

      final productName = (data['name'] ?? data['productName'] ?? '').toString();
      final category = (data['category'] ?? 'Boshqa').toString();
      final costPrice = (data['originalPrice'] ?? data['costPrice'] ?? 0) as num;
      final salePrice = (data['sellingPrice'] ?? data['salePrice'] ?? 0) as num;
      final unitType = (data['unitType'] ?? 'Dona').toString();

      if (productName.isNotEmpty) {
        _nameController.text = productName;
      }
      _costPriceController.text = costPrice.toStringAsFixed(0);
      _salePriceController.text = salePrice.toStringAsFixed(0);
      _calculateProfit();

      final newUnit = ['KG', 'Dona', 'LITR', 'Metr'].contains(unitType) ? unitType : 'Dona';
      if (mounted) {
        setState(() {
          _selectedCategory = category;
          _selectedType = newUnit;
        });
      }
    } catch (_) {
    }
  }

  void _calculateProfit() {
    final cost = num.tryParse(_costPriceController.text.replaceAll(' ', '')) ?? 0;
    final sale = num.tryParse(_salePriceController.text.replaceAll(' ', '')) ?? 0;
    setState(() {
      _profitPerUnit = sale - cost;
    });
  }

  /// Draft qiymatlarini formga yuklaydi (tahrirlash uchun)
  void _fillFormForEdit(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    _suppressBarcodeLookup = true;
    setState(() {
      _editingDraftId = doc.id;
      _nameController.text = data['name'] ?? '';
      _quantityController.text = (data['quantity'] ?? '').toString();
      _costPriceController.text = (data['costPrice'] ?? '').toString();
      _salePriceController.text = (data['salePrice'] ?? '').toString();
      _barcodeController.text = data['barcode'] ?? '';
      _selectedType = data['unitType'] ?? 'Dona';
      _selectedCategory = data['category'];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suppressBarcodeLookup = false;
    });
    _calculateProfit();
  }

  /// Formni tozalash + tahrirlash rejimini o'chirish
  void _clearForm() {
    _suppressBarcodeLookup = true;
    setState(() {
      _editingDraftId = null;
      _profitPerUnit = 0;
      _selectedType = 'Dona';
    });
    _nameController.clear();
    _quantityController.clear();
    _costPriceController.clear();
    _salePriceController.clear();
    _barcodeController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suppressBarcodeLookup = false;
    });
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

  Future<void> _onNextPressed() async {
    if (_nameController.text.trim().isEmpty ||
        _quantityController.text.trim().isEmpty ||
        _costPriceController.text.trim().isEmpty ||
        _salePriceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('adding_page.fill_required', 'Please fill all required fields!')),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final name = _nameController.text.trim();
      final quantity = num.tryParse(_quantityController.text.trim()) ?? 0;
      final costPrice = num.tryParse(_costPriceController.text.trim()) ?? 0;
      final salePrice = num.tryParse(_salePriceController.text.trim()) ?? 0;
      final profit = salePrice - costPrice;
      final barcode = _barcodeController.text.trim();
      final category = _selectedCategory ?? 'Boshqa';

      if (_editingDraftId != null) {
        // Mavjud draftni yangilash (tahrirlash rejimi)
        await TenantFirestore.draftProducts.doc(_editingDraftId).update({
          'name': name,
          'quantity': quantity,
          'unitType': _selectedType,
          'category': category,
          'costPrice': costPrice,
          'salePrice': salePrice,
          'profit': profit,
          'barcode': barcode,
        });
      } else {
        // Yangi draft qo'shish
        await TenantFirestore.draftProducts.add({
          'name': name,
          'quantity': quantity,
          'unitType': _selectedType,
          'category': category,
          'costPrice': costPrice,
          'salePrice': salePrice,
          'profit': profit,
          'barcode': barcode,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Formni tozalash
      _clearForm();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_editingDraftId != null
                ? _tr('adding_page.draft_updated', 'Mahsulot yangilandi!')
                : _tr('adding_page.added_to_draft', 'Product added to Last Actions list')),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _onAddToStockPressed(List<QueryDocumentSnapshot<Map<String, dynamic>>> drafts) async {
    if (drafts.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();

    String username = 'Unknown';
    try {
      final profile = await TenantFirestore.userDocument.get();
      username = (profile.data()?['username'] ?? 'Unknown').toString();
    } catch (_) {}

    for (final doc in drafts) {
      final data = doc.data();

      final quantity = data['quantity'] as num? ?? 0;
      final costPrice = data['costPrice'] as num? ?? 0;
      final salePrice = data['salePrice'] as num? ?? 0;
      final productName = (data['name'] ?? '').toString();
      final barcode = (data['barcode'] ?? '').toString().trim();
      final unitType = data['unitType'] ?? 'Dona';
      final category = data['category'] ?? 'Boshqa';
      final profit = data['profit'] ?? 0;

      DocumentReference productRef;
      num totalQuantity;

      if (barcode.isNotEmpty) {
        final existingSnapshot = await TenantFirestore.products
            .where('barcode', isEqualTo: barcode)
            .limit(1)
            .get();

        if (existingSnapshot.docs.isNotEmpty) {
          final existingDoc = existingSnapshot.docs.first;
          final existingData = existingDoc.data();
          final existingQty = (existingData['quantity'] as num?) ?? 0;
          productRef = existingDoc.reference;
          totalQuantity = existingQty + quantity;

          String status = 'normal';
          if (totalQuantity == 0) {
            status = 'tugagan';
          } else if (totalQuantity <= 10) {
            status = 'kam';
          }

          final attempts = ((existingData['attempts'] as num?) ?? 0).toInt() + 1;

          batch.update(productRef, {
            'name': productName,
            'productName': productName,
            'quantity': totalQuantity,
            'unitType': unitType,
            'category': category,
            'originalPrice': costPrice,
            'costPrice': costPrice,
            'sellingPrice': salePrice,
            'salePrice': salePrice,
            'profit': profit,
            'barcode': barcode,
            'status': status,
            'lastUpdate': FieldValue.serverTimestamp(),
            'attempts': attempts,
          });
        } else {
          productRef = TenantFirestore.products.doc();
          totalQuantity = quantity;

          String status = 'normal';
          if (quantity == 0) {
            status = 'tugagan';
          } else if (quantity <= 10) {
            status = 'kam';
          }

          batch.set(productRef, {
            'name': productName,
            'productName': productName,
            'quantity': quantity,
            'unitType': unitType,
            'category': category,
            'originalPrice': costPrice,
            'costPrice': costPrice,
            'sellingPrice': salePrice,
            'salePrice': salePrice,
            'profit': profit,
            'barcode': barcode,
            'status': status,
            'lastUpdate': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'attempts': 1,
          });
        }
      } else {
        productRef = TenantFirestore.products.doc();
        totalQuantity = quantity;

        String status = 'normal';
        if (quantity == 0) {
          status = 'tugagan';
        } else if (quantity <= 10) {
          status = 'kam';
        }

        batch.set(productRef, {
          'name': productName,
          'productName': productName,
          'quantity': quantity,
          'unitType': unitType,
          'category': category,
          'originalPrice': costPrice,
          'costPrice': costPrice,
          'sellingPrice': salePrice,
          'salePrice': salePrice,
          'profit': profit,
          'barcode': barcode,
          'status': status,
          'lastUpdate': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'attempts': 1,
        });
      }

      final entryRef = TenantFirestore.inventoryEntries.doc();
      batch.set(entryRef, {
        'type': 'incoming',
        'productId': productRef.id,
        'productName': productName,
        'quantity': quantity,
        'originalPrice': costPrice,
        'sellingPrice': salePrice,
        'totalValue': (quantity * costPrice).toDouble(),
        'profitPerUnit': (salePrice - costPrice).toDouble(),
        'user': username,
        'timestamp': FieldValue.serverTimestamp(),
      });

      batch.delete(doc.reference);
    }

    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('adding_page.added_to_stock_success', 'Products added to stock successfully!')),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final _ = context.locale; // Subscribe to EasyLocalization locale changes
    final isDark = ThemeController.instance.isDarkMode;

    final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
    final borderColor = isDark ? SmartStoreColors.darkDivider : const Color(0xFFE2E8F0);
    final inputBg = isDark ? SmartStoreColors.darkBackground : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Form Card ──
            Container(
              padding: const EdgeInsets.all(24),
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
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _editingDraftId != null
                                ? _tr('adding_page.edit_title', 'Mahsulotni tahrirlash')
                                : _tr('adding_page.title', 'Mahsulot ma\'lumotlari'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: SmartStoreColors.primary,
                            ),
                          ),
                        ),
                        if (_editingDraftId != null)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
                            tooltip: 'Bekor qilish',
                            onPressed: _clearForm,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Product Name
                    _buildLabel(_tr('adding_page.product_name', 'Product Name'), isDark),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                      ),
                      decoration: _buildInputDecoration(
                        hint: _tr('adding_page.product_name_hint', 'Mahsulot nomini kiriting'),
                        inputBg: inputBg,
                        borderColor: borderColor,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Row: Miqdor & Type
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel(_tr('adding_page.quantity', 'Miqdor'), isDark),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _quantityController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                                ),
                                decoration: _buildInputDecoration(
                                  hint: _tr('adding_page.quantity_hint', 'Miqdorni kiriting'),
                                  inputBg: inputBg,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel(_tr('adding_page.type', 'Type'), isDark),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedType,
                                dropdownColor: cardBg,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                                ),
                                decoration: _buildInputDecoration(
                                  hint: _tr('adding_page.type_select', 'Tanlang'),
                                  inputBg: inputBg,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                ),
                                items: ['KG', 'Dona', 'LITR', 'Metr'].map((type) {
                                  return DropdownMenuItem(
                                    value: type,
                                    child: Text(type),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedType = val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row: Kategoriya & Barcode
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel(_tr('adding_page.category', 'Kategoriya'), isDark),
                              const SizedBox(height: 6),
                              StreamBuilder<QuerySnapshot>(
                                stream: TenantFirestore.categories.snapshots(),
                                builder: (context, snapshot) {
                                  final categoryDocs = snapshot.data?.docs ?? [];
                                  final categories = categoryDocs.map((doc) => doc['name'] as String).toList();
                                  
                                  if (_selectedCategory == null && categories.isNotEmpty) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (mounted) setState(() => _selectedCategory = categories.first);
                                    });
                                  }

                                  return DropdownButtonFormField<String>(
                                    initialValue: categories.contains(_selectedCategory) ? _selectedCategory : categories.firstOrNull,
                                    dropdownColor: cardBg,
                                    borderRadius: BorderRadius.circular(16),
                                    elevation: 8,
                                    menuMaxHeight: 300,
                                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: isDark ? SmartStoreColors.darkTextSecondary : SmartStoreColors.lightTextSecondary),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                                    ),
                                    decoration: _buildInputDecoration(
                                      hint: _tr('adding_page.category_select', 'Kategoriya tanlang'),
                                      inputBg: inputBg,
                                      borderColor: borderColor,
                                      isDark: isDark,
                                    ),
                                    items: categories.map((cat) {
                                      return DropdownMenuItem(
                                        value: cat,
                                        child: Text(cat),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedCategory = val);
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel(_tr('adding_page.barcode', 'Barcode (faqat raqam)'), isDark),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _barcodeController,
                                keyboardType: TextInputType.number,
                                maxLength: 13,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                                ),
                                decoration: _buildInputDecoration(
                                  hint: _tr('adding_page.barcode_hint', 'Barcode\'ni kiriting (faqat raqam)'),
                                  inputBg: inputBg,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                ).copyWith(counterText: ""),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Row: Asl narx & Sotish narx
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel(_tr('adding_page.cost_price', 'Asl narx (bitta uchun)'), isDark),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _costPriceController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                                ),
                                decoration: _buildInputDecoration(
                                  hint: _tr('adding_page.cost_price_hint', 'Asl narxni kiriting'),
                                  inputBg: inputBg,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel(_tr('adding_page.sale_price', 'Sotish narx (bitta uchun)'), isDark),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _salePriceController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                                ),
                                decoration: _buildInputDecoration(
                                  hint: _tr('adding_page.sale_price_hint', 'Sotish narxni kiriting'),
                                  inputBg: inputBg,
                                  borderColor: borderColor,
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Zarar bo'lganda ogohlantirish
                    if (_profitPerUnit < 0 && _costPriceController.text.isNotEmpty && _salePriceController.text.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _tr('adding_page.warning_loss_title', 'Ogohlantirish: Zarar bo\'ladi!'),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _tr('adding_page.warning_loss_desc', 'Asl narx sotish narxdan katta — bu mahsulotdan foyda emas, ZARAR qilib yuborasiz. Davom etishdan avval narxlarni qaytadan tekshiring.'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: isDark ? SmartStoreColors.darkTextSecondary : const Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Foyda (bitta uchun)
                    _buildLabel(_tr('adding_page.profit', 'Foyda (bitta uchun)'), isDark),
                    const SizedBox(height: 6),
                    TextField(
                      readOnly: true,
                      controller: TextEditingController(
                        text: _profitPerUnit >= 0
                            ? '+${_profitPerUnit.toInt()}'
                            : '${_profitPerUnit.toInt()}',
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _profitPerUnit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: inputBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _profitPerUnit >= 0
                                ? (_profitPerUnit > 0 ? const Color(0xFF10B981) : borderColor)
                                : const Color(0xFFEF4444),
                            width: _profitPerUnit == 0 ? 1 : 1.5,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _profitPerUnit >= 0
                                ? (_profitPerUnit > 0 ? const Color(0xFF10B981).withOpacity(0.5) : borderColor)
                                : const Color(0xFFEF4444).withOpacity(0.6),
                            width: _profitPerUnit == 0 ? 1 : 1.5,
                          ),
                        ),
                        suffixIcon: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: (_profitPerUnit >= 0
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444))
                                .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _profitPerUnit >= 0
                                    ? Icons.auto_awesome_rounded
                                    : Icons.trending_down_rounded,
                                size: 14,
                                color: _profitPerUnit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _profitPerUnit >= 0
                                    ? _tr('adding_page.auto_calculated', 'Avtomatik hisoblanadi')
                                    : _tr('adding_page.warning_loss', 'ZARAR!'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _profitPerUnit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Next / Saqlash Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _onNextPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _editingDraftId != null
                              ? const Color(0xFF10B981)
                              : SmartStoreColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _editingDraftId != null
                                        ? Icons.save_rounded
                                        : Icons.arrow_forward_rounded,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _editingDraftId != null
                                        ? _tr('adding_page.save', 'Saqlash')
                                        : _tr('adding_page.next', 'Next →'),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Last Actions Card ──
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: TenantFirestore.draftProducts.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                final drafts = snapshot.data?.docs ?? [];

                return Container(
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
                      // Last Actions Header
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Text(
                              _tr('adding_page.last_actions', 'Last Actions'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              height: 40,
                              child: ElevatedButton.icon(
                                onPressed: drafts.isEmpty ? null : () => _onAddToStockPressed(drafts),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SmartStoreColors.primary,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(horizontal: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.all_inbox_rounded, size: 18),
                                label: Text(
                                  _tr('adding_page.add_to_stock', 'Add to Stock'),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Table Header
                      Container(
                        color: isDark ? SmartStoreColors.darkBackground : const Color(0xFFF8FAFC),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text(
                                _tr('adding_page.col_num', '#'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            Expanded(
                              flex: 3,
                              child: Text(
                                _tr('adding_page.col_name', 'Nom'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
                                ),
                              ),
                            ),

                            Expanded(
                              flex: 2,
                              child: Text(
                                _tr('adding_page.col_quantity', 'Miqdor'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
                                ),
                              ),
                            ),

                            Expanded(
                              flex: 2,
                              child: Text(
                                _tr('adding_page.col_total_price', 'Jami narx'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
                                ),
                              ),
                            ),

                            Expanded(
                              flex: 2,
                              child: Text(
                                _tr('adding_page.col_total_profit', 'Jami foyda'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
                                ),
                              ),
                            ),

                            Expanded(
                              flex: 2,
                              child: Text(
                                _tr('adding_page.col_category', 'Kategoriya'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
                                ),
                              ),
                            ),

                            Expanded(
                              flex: 2,
                              child: Text(
                                _tr('adding_page.col_time', 'Vaqt'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
                                ),
                              ),
                            ),

                            const SizedBox(width: 36),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Draft Table Content
                      if (drafts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(36),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.inbox_outlined, size: 44, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                                const SizedBox(height: 10),
                                Text(
                                  _tr('adding_page.no_drafts', 'Hozircha navbatdagi mahsulotlar yo\'q'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
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
                          itemCount: drafts.length,
                          separatorBuilder: (_, index) => Divider(height: 1, color: borderColor.withOpacity(0.5)),
                          itemBuilder: (context, index) {
                            final doc = drafts[index];
                            final data = doc.data();

                            final name = data['name'] ?? '';
                            final quantity = data['quantity'] as num? ?? 0;
                            final unitType = data['unitType'] ?? 'Dona';
                            final salePrice = data['salePrice'] as num? ?? 0;
                            final profit = data['profit'] as num? ?? 0;
                            final category = data['category'] ?? 'Boshqa';
                            final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

                            final totalPrice = quantity * salePrice;
                            final totalProfit = quantity * profit;
                            final formattedTime = DateFormat('dd MMM yyyy, HH:mm').format(createdAt);

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Nom
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                                      ),
                                    ),
                                  ),

                                  // Miqdor
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '$quantity $unitType',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                                      ),
                                    ),
                                  ),

                                  // Jami narx
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _formatCurrency(totalPrice),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
                                      ),
                                    ),
                                  ),

                                  // Jami foyda (Green if profit, Red if loss)
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _formatCurrency(totalProfit),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: totalProfit >= 0
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFFEF4444),
                                      ),
                                    ),
                                  ),

                                  // Kategoriya Badge
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: SmartStoreColors.primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          category,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: SmartStoreColors.primary,
                                          ),
                                        ),

                                      ),
                                    ),
                                  ),

                                  // Vaqt
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      formattedTime,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
                                      ),
                                    ),
                                  ),

                                  // Amallar (Tahrirlash / O'chirish)
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
                                      color: isDark ? SmartStoreColors.darkSurface : Colors.white,
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
                                                _tr('adding_page.edit', 'Tahrirlash'),
                                                style: TextStyle(
                                                  fontSize: 13,
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
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 16,
                                                color: Color(0xFFEF4444),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                _tr('adding_page.delete', 'O\'chirish'),
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
                                          _fillFormForEdit(doc);
                                        } else if (value == 'delete') {
                                          doc.reference.delete();
                                          // Agar bu tahrirlayotgan draft bo'lsa, formni tozalash
                                          if (_editingDraftId == doc.id) {
                                            _clearForm();
                                          }
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
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label, bool isDark) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? SmartStoreColors.darkTextPrimary : SmartStoreColors.lightTextPrimary,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    required Color inputBg,
    required Color borderColor,
    required bool isDark,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 13,
        color: isDark ? SmartStoreColors.darkTextMuted : SmartStoreColors.lightTextMuted,
      ),
      filled: true,
      fillColor: inputBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
    );
  }
}

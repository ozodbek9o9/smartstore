import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/tenant_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:smart_store/screens/theme_controller.dart';
import '../main.dart' show SmartStoreColors;
import '../utils/notification_controller.dart';
import 'widgets/customer_details_modal.dart';

class Customer {
  final String id;
  final String fullName;
  final String status; // 'doimiy', 'yangi', 'active'
  final num totalDebt;
  final num paidDebt;
  final num remainingDebt;
  final DateTime lastActivity;
  final DateTime createdAt;

  Customer({
    required this.id,
    required this.fullName,
    required this.status,
    required this.totalDebt,
    required this.paidDebt,
    required this.remainingDebt,
    required this.lastActivity,
    required this.createdAt,
  });

  factory Customer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final total = (data['totalDebt'] ?? data['jamiQarz'] ?? 0) as num;
    final paid = (data['paidDebt'] ?? data['tolaganQarz'] ?? 0) as num;
    final remaining =
        (data['remainingDebt'] ?? data['qolganQarz'] ?? (total - paid)) as num;

    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return Customer(
      id: doc.id,
      fullName: (data['fullName'] ?? data['name'] ?? 'Noma\'lum') as String,
      status: (data['status'] ?? 'doimiy') as String,
      totalDebt: total,
      paidDebt: paid,
      remainingDebt: remaining,
      lastActivity: parseDate(
        data['lastActivity'] ?? data['last_activity'] ?? data['createdAt'],
      ),
      createdAt: parseDate(data['createdAt']),
    );
  }
}

class _DuplicateCustomerException implements Exception {
  const _DuplicateCustomerException();
}

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'has_debt', 'no_debt'
  String _sortBy =
      'name_asc'; // 'name_asc', 'name_desc', 'debt_desc', 'debt_asc'

  final Set<String> _selectedCustomerIds = {};
  bool _isAllSelected = false;

  StreamSubscription? _customersSub;
  List<Customer> _allCustomers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    _subscribeToCustomers();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    _customersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeToCustomers() {
    _customersSub = TenantFirestore.customers.snapshots().listen(
      (snapshot) {
        final list = snapshot.docs
            .map((doc) => Customer.fromFirestore(doc))
            .toList();
        if (mounted) {
          setState(() {
            _allCustomers = list;
            _isLoading = false;
          });
          _checkOverdueNotifications(list);
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      },
    );
  }

  void _checkOverdueNotifications(List<Customer> customers) {
    final now = DateTime.now();
    final alerts = <NotificationAlert>[];

    for (final c in customers) {
      if (c.remainingDebt > 0) {
        final diffDays = now.difference(c.lastActivity).inDays;
        if (diffDays >= 30) {
          alerts.add(
            NotificationAlert(
              id: c.id,
              customerName: c.fullName,
              remainingDebt: c.remainingDebt,
              lastActivity: c.lastActivity,
              customText: '',
            ),
          );
        }
      }
    }

    NotificationController.instance.updateOverdueCustomers(alerts);
  }

  void _showCustomerDetails(Customer c) {
    showDialog(
      context: context,
      builder: (context) => CustomerDetailsModal(
        customer: {
          'id': c.id,
          'fullName': c.fullName,
          'totalDebt': c.totalDebt,
          'remainingDebt': c.remainingDebt,
        },
      ),
    );
  }

  // ── Helper formatters ──
  String _tr(String key, String fallback) {
    final val = key.tr();
    return (val == key || val.isEmpty) ? fallback : val;
  }

  String _formatCurrency(num amount) {
    final intVal = amount.round();
    final str = intVal.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }
    return '${intVal < 0 ? "-" : ""}${buffer.toString()} UZS';
  }

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = (dt.year % 100).toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'M';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  // ── Filtered & Sorted Customers List ──
  List<Customer> get _filteredCustomers {
    var result = _allCustomers.where((c) {
      if (_searchQuery.isNotEmpty) {
        if (!c.fullName.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }
      if (_statusFilter == 'has_debt' && c.remainingDebt <= 0) return false;
      if (_statusFilter == 'no_debt' && c.remainingDebt > 0) return false;
      return true;
    }).toList();

    // Default: Alphabetical order (A -> Z)
    result.sort((a, b) {
      switch (_sortBy) {
        case 'name_desc':
          return b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase());
        case 'debt_desc':
          return b.remainingDebt.compareTo(a.remainingDebt);
        case 'debt_asc':
          return a.remainingDebt.compareTo(b.remainingDebt);
        case 'name_asc':
        default:
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      }
    });

    return result;
  }

  // ── Delete Selected Customers ──
  Future<void> _deleteSelectedCustomers() async {
    if (_selectedCustomerIds.isEmpty) return;

    final count = _selectedCustomerIds.length;
    final isDark = ThemeController.instance.isDarkMode;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? SmartStoreColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? SmartStoreColors.darkDivider
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFEF4444),
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _tr(
                  'customers.delete_selected',
                  'Delete Customers',
                ).replaceFirst('{0}', '$count'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? SmartStoreColors.darkTextPrimary
                      : SmartStoreColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tanlangan $count ta mijozni o\'chirishga ishonchingiz komilmi?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
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
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(_tr('customers.cancel', 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        _tr(
                          'customers.delete_selected',
                          'Delete',
                        ).replaceFirst(' ({0})', ''),
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

    if (confirm == true) {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in _selectedCustomerIds) {
        batch.delete(TenantFirestore.customers.doc(id));
      }
      await batch.commit();

      setState(() {
        _selectedCustomerIds.clear();
        _isAllSelected = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'customers.deleted_count',
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
    }
  }

  // ── Add Customer Modal ──
  void _showAddCustomerModal() {
    final isDark = ThemeController.instance.isDarkMode;
    final nameController = TextEditingController();
    final debtController = TextEditingController();
    final paidController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? SmartStoreColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? SmartStoreColors.darkDivider
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
                    blurRadius: 36,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Modal Header
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: SmartStoreColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_add_rounded,
                          color: SmartStoreColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _tr('customers.add_modal_title', 'Add New Customer'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? SmartStoreColors.darkTextPrimary
                                : SmartStoreColors.lightTextPrimary,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? SmartStoreColors.darkSurfaceVariant
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: isDark
                                ? SmartStoreColors.darkTextSecondary
                                : SmartStoreColors.lightTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Input: Full Name
                  Text(
                    _tr('customers.full_name', 'Full Name'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? SmartStoreColors.darkTextSecondary
                          : SmartStoreColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? SmartStoreColors.darkTextPrimary
                          : SmartStoreColors.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: _tr(
                        'customers.full_name_hint',
                        'Enter full name',
                      ),
                      hintStyle: TextStyle(
                        fontSize: 14,
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
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? SmartStoreColors.darkDivider
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? SmartStoreColors.darkDivider
                              : const Color(0xFFE2E8F0),
                        ),
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

                  const SizedBox(height: 14),

                  // Input: Initial Total Debt (Optional)
                  Text(
                    _tr('customers.initial_debt', 'Initial Total Debt (UZS)'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? SmartStoreColors.darkTextSecondary
                          : SmartStoreColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: debtController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? SmartStoreColors.darkTextPrimary
                          : SmartStoreColors.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: '0 UZS',
                      hintStyle: TextStyle(
                        fontSize: 14,
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
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? SmartStoreColors.darkDivider
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? SmartStoreColors.darkDivider
                              : const Color(0xFFE2E8F0),
                        ),
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

                  const SizedBox(height: 14),

                  // Input: Initial Paid Debt (Optional)
                  Text(
                    _tr('customers.initial_paid', 'Initial Paid Debt (UZS)'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? SmartStoreColors.darkTextSecondary
                          : SmartStoreColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: paidController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? SmartStoreColors.darkTextPrimary
                          : SmartStoreColors.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: '0 UZS',
                      hintStyle: TextStyle(
                        fontSize: 14,
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
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? SmartStoreColors.darkDivider
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? SmartStoreColors.darkDivider
                              : const Color(0xFFE2E8F0),
                        ),
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

                  // Submit Button
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final name = nameController.text.trim();
                              if (name.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _tr(
                                        'customers.enter_name_error',
                                        'Please enter customer full name',
                                      ),
                                    ),
                                    backgroundColor: SmartStoreColors.danger,
                                  ),
                                );
                                return;
                              }

                              setModalState(() => isSubmitting = true);

                              final normalizedName = name
                                  .replaceAll(RegExp(r'\s+'), ' ')
                                  .trim()
                                  .toLowerCase();

                              final total =
                                  num.tryParse(
                                    debtController.text.replaceAll(
                                      RegExp(r'[^0-9.]'),
                                      '',
                                    ),
                                  ) ??
                                  0;
                              final paid =
                                  num.tryParse(
                                    paidController.text.replaceAll(
                                      RegExp(r'[^0-9.]'),
                                      '',
                                    ),
                                  ) ??
                                  0;
                              final remaining = total > paid ? total - paid : 0;

                              try {
                                final customersSnapshot = await TenantFirestore
                                    .customers
                                    .get();
                                final duplicate = customersSnapshot.docs.any((
                                  doc,
                                ) {
                                  final data = doc.data();
                                  final existingName =
                                      (data['fullName'] ?? data['name'] ?? '')
                                          .toString()
                                          .replaceAll(RegExp(r'\s+'), ' ')
                                          .trim()
                                          .toLowerCase();
                                  return existingName == normalizedName;
                                });
                                if (duplicate) {
                                  throw const _DuplicateCustomerException();
                                }

                                await FirebaseFirestore.instance.runTransaction(
                                  (transaction) async {
                                    final customerRef = TenantFirestore
                                        .customers
                                        .doc();
                                    transaction.set(customerRef, {
                                      'fullName': name,
                                      'normalizedName': normalizedName,
                                      'status': 'doimiy',
                                      'totalDebt': total,
                                      'paidDebt': paid,
                                      'remainingDebt': remaining,
                                      'lastActivity':
                                          FieldValue.serverTimestamp(),
                                      'createdAt': FieldValue.serverTimestamp(),
                                    });
                                  },
                                );
                              } on _DuplicateCustomerException {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _tr(
                                          'customers.duplicate_name',
                                          'Bu mijoz allaqachon mavjud',
                                        ),
                                      ),
                                      backgroundColor: SmartStoreColors.danger,
                                    ),
                                  );
                                }
                                setModalState(() => isSubmitting = false);
                                return;
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: SmartStoreColors.danger,
                                    ),
                                  );
                                }
                                setModalState(() => isSubmitting = false);
                                return;
                              }

                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _tr(
                                        'customers.customer_added',
                                        'Customer added successfully',
                                      ),
                                    ),
                                    backgroundColor: SmartStoreColors.success,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SmartStoreColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _tr('customers.add_button', 'Add Customer'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _ = context.locale; // Subscribe to EasyLocalization locale changes
    final isDark = ThemeController.instance.isDarkMode;
    final customers = _filteredCustomers;

    // Stat Totals
    final totalCustomersCount = _allCustomers.length;
    num grandTotalDebt = 0;
    num grandPaidDebt = 0;
    num grandRemainingDebt = 0;

    for (final c in _allCustomers) {
      grandTotalDebt += c.totalDebt;
      grandPaidDebt += c.paidDebt;
      grandRemainingDebt += c.remainingDebt;
    }

    final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
    final borderColor = isDark
        ? SmartStoreColors.darkDivider
        : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header Row ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr('customers.title', 'Customers'),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? SmartStoreColors.darkTextPrimary
                              : SmartStoreColors.lightTextPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tr(
                          'customers.subtitle',
                          'Mijozlar ro\'yxati va qarz (debt) ma\'lumotlari',
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? SmartStoreColors.darkTextMuted
                              : SmartStoreColors.lightTextMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Top Toolbar Actions (Delete if selected, else Add Customer)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedCustomerIds.isNotEmpty) ...[
                      SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _deleteSelectedCustomers,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _tr(
                              'customers.delete_selected',
                              'Delete ({0})',
                            ).replaceFirst(
                              '{0}',
                              '${_selectedCustomerIds.length}',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],

                    SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _showAddCustomerModal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SmartStoreColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: Text(
                          _tr('customers.add_customer', 'Add Customer'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Top 4 Stat Cards Row ──
            Row(
              children: [
                // Card 1: Jami mijozlar
                Expanded(
                  child: _StatCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    isDark: isDark,
                    icon: Icons.people_alt_outlined,
                    iconBg: const Color(0xFF8B5CF6).withOpacity(0.12),
                    iconColor: const Color(0xFF8B5CF6),
                    title: _tr('customers.total_customers', 'Total Customers'),
                    value: '$totalCustomersCount',
                    subtitle: _tr(
                      'customers.active_customers',
                      'Active customers',
                    ),
                    valueColor: isDark
                        ? SmartStoreColors.darkTextPrimary
                        : SmartStoreColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(width: 12),

                // Card 2: Umumiy qarz (Normal Color)
                Expanded(
                  child: _StatCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    isDark: isDark,
                    icon: Icons.account_balance_wallet_outlined,
                    iconBg: const Color(0xFFEF4444).withOpacity(0.12),
                    iconColor: const Color(0xFFEF4444),
                    title: _tr('customers.total_debt', 'Total Debt'),
                    value: _formatCurrency(grandTotalDebt),
                    subtitle: 'UZS',
                    valueColor: isDark
                        ? SmartStoreColors.darkTextPrimary
                        : SmartStoreColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(width: 12),

                // Card 3: To'langan qarz (GREEN Color)
                Expanded(
                  child: _StatCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    isDark: isDark,
                    icon: Icons.history_rounded,
                    iconBg: const Color(0xFF10B981).withOpacity(0.12),
                    iconColor: const Color(0xFF10B981),
                    title: _tr('customers.paid_debt', 'Paid (30 days)'),
                    value: _formatCurrency(grandPaidDebt),
                    subtitle: 'UZS',
                    valueColor: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 12),

                // Card 4: Muddati o'tgan / Qolgan qarz (RED Color)
                Expanded(
                  child: _StatCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    isDark: isDark,
                    icon: Icons.hourglass_empty_rounded,
                    iconBg: const Color(0xFFF59E0B).withOpacity(0.12),
                    iconColor: const Color(0xFFF59E0B),
                    title: _tr('customers.overdue_debt', 'Overdue Debt'),
                    value: _formatCurrency(grandRemainingDebt),
                    subtitle: 'UZS',
                    valueColor: const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Main Customer Table Card ──
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Table Toolbar: Search & Filters
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        // Search Input
                        Expanded(
                          flex: 3,
                          child: SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) =>
                                  setState(() => _searchQuery = val),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? SmartStoreColors.darkTextPrimary
                                    : SmartStoreColors.lightTextPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: _tr(
                                  'customers.search_hint',
                                  'Search customer...',
                                ),
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
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: SmartStoreColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Status Filter Dropdown
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? SmartStoreColors.darkBackground
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _statusFilter,
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: isDark
                                    ? SmartStoreColors.darkTextSecondary
                                    : SmartStoreColors.lightTextSecondary,
                              ),
                              dropdownColor: cardBg,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? SmartStoreColors.darkTextPrimary
                                    : SmartStoreColors.lightTextPrimary,
                              ),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _statusFilter = val);
                                }
                              },
                              items: [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text(
                                    _tr('customers.filter_all', 'All statuses'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'has_debt',
                                  child: Text(
                                    _tr(
                                      'customers.filter_has_debt',
                                      'Has debt',
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'no_debt',
                                  child: Text(
                                    _tr('customers.filter_no_debt', 'No debt'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Sorting Dropdown (Default: A -> Z)
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? SmartStoreColors.darkBackground
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _sortBy,
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: isDark
                                    ? SmartStoreColors.darkTextSecondary
                                    : SmartStoreColors.lightTextSecondary,
                              ),
                              dropdownColor: cardBg,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? SmartStoreColors.darkTextPrimary
                                    : SmartStoreColors.lightTextPrimary,
                              ),
                              onChanged: (val) {
                                if (val != null) setState(() => _sortBy = val);
                              },
                              items: [
                                DropdownMenuItem(
                                  value: 'name_asc',
                                  child: Text(
                                    _tr(
                                      'customers.sort_name_asc',
                                      'Alphabetical (A → Z)',
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'name_desc',
                                  child: Text(
                                    _tr(
                                      'customers.sort_name_desc',
                                      'Alphabetical (Z → A)',
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'debt_desc',
                                  child: Text(
                                    _tr(
                                      'customers.sort_debt_desc',
                                      'Debt (High → Low)',
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'debt_asc',
                                  child: Text(
                                    _tr(
                                      'customers.sort_debt_asc',
                                      'Debt (Low → High)',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Table Header
                  Container(
                    color: isDark
                        ? SmartStoreColors.darkBackground.withOpacity(0.5)
                        : const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // Checkbox Header
                        SizedBox(
                          width: 36,
                          child: Checkbox(
                            value: _isAllSelected,
                            onChanged: (val) {
                              setState(() {
                                _isAllSelected = val ?? false;
                                if (_isAllSelected) {
                                  _selectedCustomerIds.addAll(
                                    customers.map((c) => c.id),
                                  );
                                } else {
                                  _selectedCustomerIds.clear();
                                }
                              });
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Mijoz Column
                        Expanded(
                          flex: 3,
                          child: Text(
                            _tr('customers.col_customer', 'Customer'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Jami Qarz Column
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('customers.col_total_debt', 'Total Debt'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // To'langan Qarz Column (Green)
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('customers.col_paid_debt', 'Paid Debt'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Qolgan Qarz Column (Red)
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr(
                              'customers.col_remaining_debt',
                              'Remaining Debt',
                            ),
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
                            _tr('customers.col_status', 'Status'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Oxirgi Faoliyat Column (dd/MM/yy HH:mm)
                        Expanded(
                          flex: 2,
                          child: Text(
                            _tr('customers.col_last_activity', 'Last Activity'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ),

                        // Actions
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Table Body (Scroll view after 8 items)
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (customers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.people_outline_rounded,
                              size: 48,
                              color: isDark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _tr(
                                'customers.no_customers',
                                'No customers available yet',
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
                  else if (customers.length > 8)
                    SizedBox(
                      height: 520,
                      child: ListView.separated(
                        itemCount: customers.length,
                        separatorBuilder: (_, index) => Divider(
                          height: 1,
                          color: borderColor.withOpacity(0.5),
                        ),
                        itemBuilder: (context, index) {
                          final c = customers[index];
                          final isSelected = _selectedCustomerIds.contains(
                            c.id,
                          );
                          final initials = _getInitials(c.fullName);
                          final hasDebt = c.remainingDebt > 0;

                          return Container(
                            color: isSelected
                                ? (isDark
                                      ? SmartStoreColors.primary.withOpacity(
                                          0.15,
                                        )
                                      : SmartStoreColors.primary.withOpacity(
                                          0.05,
                                        ))
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                // Checkbox
                                SizedBox(
                                  width: 36,
                                  child: Checkbox(
                                    value: isSelected,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedCustomerIds.add(c.id);
                                        } else {
                                          _selectedCustomerIds.remove(c.id);
                                        }
                                        _isAllSelected =
                                            _selectedCustomerIds.length ==
                                            customers.length;
                                      });
                                    },
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: SmartStoreColors.primary
                                              .withOpacity(0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            initials,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: SmartStoreColors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              c.fullName,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: isDark
                                                    ? SmartStoreColors
                                                          .darkTextPrimary
                                                    : SmartStoreColors
                                                          .lightTextPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Jami Qarz (Normal Color)
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _formatCurrency(c.totalDebt),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? SmartStoreColors.darkTextPrimary
                                          : SmartStoreColors.lightTextPrimary,
                                    ),
                                  ),
                                ),

                                // To'langan Qarz (GREEN Color)
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _formatCurrency(c.paidDebt),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ),

                                // Qolgan Qarz (RED Color)
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _formatCurrency(c.remainingDebt),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ),

                                // Holat (Badge: Qarz bor vs Qarz yo'q)
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
                                        color: hasDebt
                                            ? const Color(
                                                0xFFEF4444,
                                              ).withOpacity(0.12)
                                            : const Color(
                                                0xFF10B981,
                                              ).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: hasDebt
                                              ? const Color(
                                                  0xFFEF4444,
                                                ).withOpacity(0.3)
                                              : const Color(
                                                  0xFF10B981,
                                                ).withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        hasDebt
                                            ? _tr(
                                                'customers.status_has_debt',
                                                'Qarz bor',
                                              )
                                            : _tr(
                                                'customers.status_no_debt',
                                                'Qarz yo\'q',
                                              ),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: hasDebt
                                              ? const Color(0xFFEF4444)
                                              : const Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Oxirgi faoliyat (dd/MM/yy HH:mm)
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _formatDateTime(c.lastActivity),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? SmartStoreColors.darkTextMuted
                                          : SmartStoreColors.lightTextMuted,
                                    ),
                                  ),
                                ),

                                // Amallar (More icon)
                                SizedBox(
                                  width: 40,
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.more_vert_rounded,
                                      size: 18,
                                      color: isDark
                                          ? SmartStoreColors.darkTextSecondary
                                          : SmartStoreColors.lightTextSecondary,
                                    ),
                                    onPressed: () => _showCustomerDetails(c),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: customers.length,
                      separatorBuilder: (_, index) => Divider(
                        height: 1,
                        color: borderColor.withOpacity(0.5),
                      ),
                      itemBuilder: (context, index) {
                        final c = customers[index];
                        final isSelected = _selectedCustomerIds.contains(c.id);
                        final initials = _getInitials(c.fullName);
                        final hasDebt = c.remainingDebt > 0;

                        return Container(
                          color: isSelected
                              ? (isDark
                                    ? SmartStoreColors.primary.withOpacity(0.15)
                                    : SmartStoreColors.primary.withOpacity(
                                        0.05,
                                      ))
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              // Checkbox
                              SizedBox(
                                width: 36,
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedCustomerIds.add(c.id);
                                      } else {
                                        _selectedCustomerIds.remove(c.id);
                                      }
                                      _isAllSelected =
                                          _selectedCustomerIds.length ==
                                          customers.length;
                                    });
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: SmartStoreColors.primary
                                            .withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          initials,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: SmartStoreColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.fullName,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? SmartStoreColors
                                                        .darkTextPrimary
                                                  : SmartStoreColors
                                                        .lightTextPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Jami Qarz (Normal Color)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatCurrency(c.totalDebt),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? SmartStoreColors.darkTextPrimary
                                        : SmartStoreColors.lightTextPrimary,
                                  ),
                                ),
                              ),

                              // To'langan Qarz (GREEN Color)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatCurrency(c.paidDebt),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),

                              // Qolgan Qarz (RED Color)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatCurrency(c.remainingDebt),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ),

                              // Holat (Badge: Qarz bor vs Qarz yo'q)
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
                                      color: hasDebt
                                          ? const Color(
                                              0xFFEF4444,
                                            ).withOpacity(0.12)
                                          : const Color(
                                              0xFF10B981,
                                            ).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: hasDebt
                                            ? const Color(
                                                0xFFEF4444,
                                              ).withOpacity(0.3)
                                            : const Color(
                                                0xFF10B981,
                                              ).withOpacity(0.3),
                                      ),
                                    ),
                                    child: Text(
                                      hasDebt
                                          ? _tr(
                                              'customers.status_has_debt',
                                              'Qarz bor',
                                            )
                                          : _tr(
                                              'customers.status_no_debt',
                                              'Qarz yo\'q',
                                            ),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: hasDebt
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF10B981),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Oxirgi faoliyat (dd/MM/yy HH:mm)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatDateTime(c.lastActivity),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? SmartStoreColors.darkTextMuted
                                        : SmartStoreColors.lightTextMuted,
                                  ),
                                ),
                              ),

                              // Amallar (More icon)
                              SizedBox(
                                width: 40,
                                child: IconButton(
                                  icon: Icon(
                                    Icons.more_vert_rounded,
                                    size: 18,
                                    color: isDark
                                        ? SmartStoreColors.darkTextSecondary
                                        : SmartStoreColors.lightTextSecondary,
                                  ),
                                  onPressed: () => _showCustomerDetails(c),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const Divider(height: 1),

                  // Table Footer Summary
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Text(
                      _tr(
                        'customers.total_count',
                        'Jami {0} ta mijoz',
                      ).replaceFirst('{0}', '${customers.length}'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? SmartStoreColors.darkTextMuted
                            : SmartStoreColors.lightTextMuted,
                      ),
                    ),
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

// ───────────────────────────────────────────────────────────────
// Stat Card Component
// ───────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final Color cardBg;
  final Color borderColor;
  final bool isDark;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String value;
  final String subtitle;
  final Color valueColor;

  const _StatCard({
    required this.cardBg,
    required this.borderColor,
    required this.isDark,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? SmartStoreColors.darkTextMuted
                        : SmartStoreColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: valueColor,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? SmartStoreColors.darkTextMuted
                        : SmartStoreColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

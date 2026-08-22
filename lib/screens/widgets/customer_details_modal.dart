import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../models/pos_models.dart';
import '../../utils/tenant_firestore.dart';
import 'customer_payment_modal.dart';
import '../../../main.dart' show SmartStoreColors;

class CustomerDetailsModal extends StatefulWidget {
  final Map<String, dynamic> customer;

  const CustomerDetailsModal({super.key, required this.customer});

  @override
  State<CustomerDetailsModal> createState() => _CustomerDetailsModalState();
}

class _CustomerDetailsModalState extends State<CustomerDetailsModal> {
  void _openPaymentModal(
    BuildContext context, {
    CustomerDebt? debt,
    bool payAll = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CustomerPaymentModal(
        customer: widget.customer,
        specificDebt: debt,
        payAll: payAll,
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sale payment updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _openAddDebtModal(BuildContext ctx) async {
    Navigator.of(ctx).pop();
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _AddDebtModal(customer: widget.customer),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'customers.debt_added'.tr(args: ['']).isEmpty
                ? 'Qarz qo\'shildi'
                : 'customers.debt_added'.tr(),
          ),
          backgroundColor: SmartStoreColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 900,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.person, color: primaryColor),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.customer['fullName'] ?? '',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          StreamBuilder<DocumentSnapshot>(
                            stream: TenantFirestore.customers
                                .doc(widget.customer['id'])
                                .snapshots(),
                            builder: (context, snapshot) {
                              final currentTotalDebt =
                                  snapshot.data?.data() != null
                                  ? (snapshot.data!.data()
                                            as Map<
                                              String,
                                              dynamic
                                            >)['totalDebt'] ??
                                        0
                                  : widget.customer['totalDebt'] ?? 0;
                              return Text(
                                '${"customers.col_total_debt".tr()}: ${NumberFormat.currency(locale: 'uz', symbol: 'UZS', decimalDigits: 0).format(currentTotalDebt)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _openAddDebtModal(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: Text(
                          'customers.btn_add_debt'.tr().isEmpty
                              ? 'Add Debt'
                              : 'customers.btn_add_debt'.tr(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () =>
                            _openPaymentModal(context, payAll: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('customers.btn_pay_all'.tr()),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Tabs
              TabBar(
                labelColor: primaryColor,
                unselectedLabelColor: Colors.grey,
                indicatorColor: primaryColor,
                tabs: [
                  Tab(text: 'customers.tab_products'.tr()),
                  Tab(text: 'customers.tab_payments'.tr()),
                ],
              ),
              const SizedBox(height: 16),

              // Tab Views
              Expanded(
                child: TabBarView(
                  children: [
                    _buildProductsTab(isDark),
                    _buildPaymentsTab(isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsTab(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: TenantFirestore.customerDebts(
        widget.customer['id'],
      ).orderBy('purchaseDate', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final debts =
            snapshot.data?.docs
                .map((doc) => CustomerDebt.fromFirestore(doc))
                .toList() ??
            [];

        if (debts.isEmpty) {
          return Center(child: Text('customers.empty_products'.tr()));
        }

        return _buildTable(
          isDark: isDark,
          headers: [
            'customers.col_product'.tr(),
            'customers.col_quantity'.tr(),
            'customers.col_amount'.tr(),
            'customers.col_date'.tr(),
            'customers.col_action'.tr(),
          ],
          rows: debts.map((debt) {
            return DataRow(
              cells: [
                DataCell(Text(debt.productName)),
                DataCell(Text(debt.quantity?.toString() ?? '-')),
                DataCell(
                  Text(
                    NumberFormat.currency(
                      locale: 'uz',
                      symbol: 'UZS',
                      decimalDigits: 0,
                    ).format(debt.amount),
                  ),
                ),
                DataCell(
                  Text(
                    DateFormat('dd/MM/yy HH:mm:ss').format(debt.purchaseDate),
                  ),
                ),
                DataCell(
                  ElevatedButton(
                    onPressed: () => _openPaymentModal(context, debt: debt),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(80, 36),
                    ),
                    child: Text('customers.btn_pay'.tr()),
                  ),
                ),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildPaymentsTab(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: TenantFirestore.customerPayments(
        widget.customer['id'],
      ).orderBy('paymentDate', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final payments =
            snapshot.data?.docs
                .map((doc) => CustomerPayment.fromFirestore(doc))
                .toList() ??
            [];

        if (payments.isEmpty) {
          return Center(child: Text('customers.empty_payments'.tr()));
        }

        return _buildTable(
          isDark: isDark,
          headers: [
            'customers.col_product'.tr(),
            'customers.col_quantity'.tr(),
            'customers.col_amount'.tr(),
            'customers.col_date'.tr(),
          ],
          rows: payments.map((payment) {
            return DataRow(
              cells: [
                DataCell(
                  Row(
                    children: [
                      if (payment.isFullPayment)
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 16,
                        )
                      else
                        const Icon(Icons.receipt, color: Colors.grey, size: 16),
                      const SizedBox(width: 8),
                      Text(payment.productName),
                    ],
                  ),
                ),
                DataCell(Text(payment.quantity?.toString() ?? '-')),
                DataCell(
                  Text(
                    NumberFormat.currency(
                      locale: 'uz',
                      symbol: 'UZS',
                      decimalDigits: 0,
                    ).format(payment.amount),
                  ),
                ),
                DataCell(
                  Text(
                    DateFormat('dd/MM/yy HH:mm:ss').format(payment.paymentDate),
                  ),
                ),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTable({
    required bool isDark,
    required List<String> headers,
    required List<DataRow> rows,
  }) {
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            isDark ? Colors.grey[900] : Colors.grey[100],
          ),
          columns: headers
              .map(
                (h) => DataColumn(
                  label: Text(
                    h,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              )
              .toList(),
          rows: rows,
        ),
      ),
    );
  }
}

class _AddDebtModal extends StatefulWidget {
  final Map<String, dynamic> customer;
  const _AddDebtModal({required this.customer});

  @override
  State<_AddDebtModal> createState() => _AddDebtModalState();
}

class _AddDebtModalState extends State<_AddDebtModal> {
  final _productNameController = TextEditingController();
  final _priceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _productNameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final productName = _productNameController.text.trim();
      final priceStr = _priceController.text.replaceAll(RegExp(r'[^0-9.]'), '');
      final price = num.tryParse(priceStr) ?? 0;

      final customerId = widget.customer['id'];
      final customerRef = TenantFirestore.customers.doc(customerId);
      final debtRef = TenantFirestore.customerDebts(customerId).doc();

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final customerDoc = await transaction.get(customerRef);
        final data = customerDoc.data() ?? <String, dynamic>{};
        final currentTotal = (data['totalDebt'] ?? 0) as num;
        final currentRemaining = (data['remainingDebt'] ?? 0) as num;
        final currentPaid = (data['paidDebt'] ?? 0) as num;

        final newTotal = currentTotal + price;
        final newRemaining = currentRemaining + price;

        num newPaid;
        if (newTotal == 0) {
          newPaid = 0;
        } else {
          newPaid = currentPaid;
        }

        transaction.set(debtRef, {
          'productName': productName,
          'quantity': null,
          'amount': price,
          'purchaseDate': FieldValue.serverTimestamp(),
          'productId': null,
        });

        transaction.update(customerRef, {
          'totalDebt': newTotal,
          'remainingDebt': newRemaining,
          'paidDebt': newPaid,
          'lastActivity': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    final borderColor = isDark
        ? SmartStoreColors.darkDivider
        : const Color(0xFFE2E8F0);
    final inputBg = isDark
        ? SmartStoreColors.darkBackground
        : const Color(0xFFF8FAFC);
    final textPrimary = isDark
        ? SmartStoreColors.darkTextPrimary
        : SmartStoreColors.lightTextPrimary;
    final textSecondary = isDark
        ? SmartStoreColors.darkTextSecondary
        : SmartStoreColors.lightTextSecondary;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? SmartStoreColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
              blurRadius: 36,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      color: Color(0xFFF59E0B),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'customers.add_debt_title'.tr().isEmpty
                          ? 'Add New Debt'
                          : 'customers.add_debt_title'.tr(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
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
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Product name
              Text(
                'customers.debt_product_name'.tr().isEmpty
                    ? 'Product Name'
                    : 'customers.debt_product_name'.tr(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _productNameController,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'customers.debt_product_hint'.tr().isEmpty
                      ? 'e.g. Coca Cola 1L'
                      : 'customers.debt_product_hint'.tr(),
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? SmartStoreColors.darkTextMuted
                        : SmartStoreColors.lightTextMuted,
                  ),
                  filled: true,
                  fillColor: inputBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
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
                    borderSide: BorderSide(color: primary, width: 1.5),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return 'customers.err_required'.tr().isEmpty
                        ? 'Required'
                        : 'customers.err_required'.tr();
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Price
              Text(
                'customers.debt_price'.tr().isEmpty
                    ? 'Price (UZS)'
                    : 'customers.debt_price'.tr(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(fontSize: 14, color: textPrimary),
                decoration: InputDecoration(
                  hintText: '0 UZS',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? SmartStoreColors.darkTextMuted
                        : SmartStoreColors.lightTextMuted,
                  ),
                  filled: true,
                  fillColor: inputBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
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
                    borderSide: BorderSide(color: primary, width: 1.5),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return 'customers.err_required'.tr().isEmpty
                        ? 'Required'
                        : 'customers.err_required'.tr();
                  final price = num.tryParse(
                    v.replaceAll(RegExp(r'[^0-9.]'), ''),
                  );
                  if (price == null || price <= 0)
                    return 'customers.err_invalid_price'.tr().isEmpty
                        ? 'Enter valid price'
                        : 'customers.err_invalid_price'.tr();
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'customers.cancel'.tr().isEmpty
                            ? 'Cancel'
                            : 'customers.cancel'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'customers.btn_add'.tr().isEmpty
                                  ? 'Add'
                                  : 'customers.btn_add'.tr(),
                              style: const TextStyle(
                                fontSize: 15,
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
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../models/pos_models.dart';
import '../../utils/tenant_firestore.dart';

class CustomerPaymentModal extends StatefulWidget {
  final Map<String, dynamic> customer;
  final CustomerDebt? specificDebt;
  final bool payAll;

  const CustomerPaymentModal({
    super.key,
    required this.customer,
    this.specificDebt,
    this.payAll = false,
  });

  @override
  State<CustomerPaymentModal> createState() => _CustomerPaymentModalState();
}

class _CustomerPaymentModalState extends State<CustomerPaymentModal> {
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  num _targetAmount({num? currentRemainingDebt}) {
    if (widget.payAll) {
      return currentRemainingDebt ??
          widget.customer['remainingDebt'] ??
          widget.customer['totalDebt'] ??
          0;
    } else {
      return widget.specificDebt?.amount ?? 0;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _processPayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final customerId = widget.customer['id'];
      final customerRef = TenantFirestore.customers.doc(customerId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final customerDoc = await transaction.get(customerRef);
        if (!customerDoc.exists) throw Exception('Customer not found');

        final currentRemainingDebt = customerDoc.data()?['remainingDebt'] ?? 0;
        final currentPaidDebt = customerDoc.data()?['paidDebt'] ?? 0;

        if (widget.payAll) {
          // Pay all debts: if totalDebt becomes 0, paidDebt must also be 0
          transaction.update(customerRef, {
            'totalDebt': 0,
            'remainingDebt': 0,
            'paidDebt': 0,
            'lastActivity': FieldValue.serverTimestamp(),
          });

          // Keep each paid product as its own history entry.
          final debtsQuery = await TenantFirestore.customerDebts(
            customerId,
          ).get();
          for (final doc in debtsQuery.docs) {
            final debtData = doc.data();
            transaction.delete(doc.reference);
            final paymentDoc = TenantFirestore.customerPayments(
              customerId,
            ).doc();
            transaction.set(paymentDoc, {
              'productId': debtData['productId'],
              'productName': debtData['productName'] ?? '',
              'quantity': debtData['quantity'],
              'amount': debtData['amount'] ?? 0,
              'paymentDate': FieldValue.serverTimestamp(),
              'isFullPayment': false,
            });
          }
        } else {
          // Pay specific debt
          final debt = widget.specificDebt!;
          final debtRef = TenantFirestore.customerDebts(
            customerId,
          ).doc(debt.id);

          transaction.delete(debtRef);

          final paymentDoc = TenantFirestore.customerPayments(customerId).doc();
          transaction.set(paymentDoc, {
            'productId': debt.productId,
            'productName': debt.productName,
            'quantity': debt.quantity,
            'amount': debt.amount,
            'paymentDate': FieldValue.serverTimestamp(),
            'isFullPayment': false,
          });

          final newTotal = (currentRemainingDebt - debt.amount).clamp(
            0,
            double.infinity,
          );
          final newRemaining = (currentRemainingDebt - debt.amount).clamp(
            0,
            double.infinity,
          );
          final newPaid = newTotal == 0 ? 0 : (currentPaidDebt + debt.amount);

          transaction.update(customerRef, {
            'totalDebt': newTotal,
            'remainingDebt': newRemaining,
            'paidDebt': newPaid,
            'lastActivity': FieldValue.serverTimestamp(),
          });
        }
      });

      if (mounted) {
        Navigator.pop(context, true); // Return success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: TenantFirestore.customers
          .doc(widget.customer['id'] as String)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final currentRemainingDebt =
            data?['remainingDebt'] ??
            data?['totalDebt'] ??
            widget.customer['remainingDebt'] ??
            widget.customer['totalDebt'] ??
            0;
        return _buildDialog(context, currentRemainingDebt);
      },
    );
  }

  Widget _buildDialog(BuildContext context, num currentRemainingDebt) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final targetAmount = _targetAmount(
      currentRemainingDebt: currentRemainingDebt,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.payAll
                    ? 'customers.pay_all_title'.tr()
                    : 'customers.pay_item_title'.tr(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (!widget.payAll) ...[
                Text(
                  '${widget.specificDebt?.productName}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'customers.pay_amount_label'.tr(),
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: '0',
                  suffixText: 'UZS',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  final amount = double.tryParse(value);
                  if (amount == null) return 'Invalid number';
                  if (amount != targetAmount) {
                    return 'customers.err_amount_exact'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total:',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      NumberFormat.currency(
                        locale: 'uz',
                        symbol: 'UZS',
                        decimalDigits: 0,
                      ).format(targetAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: Text('customers.cancel'.tr()),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _processPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('customers.btn_confirm'.tr()),
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

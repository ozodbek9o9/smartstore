import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_store/services/offline_sales_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists queued sales once and reserves their local stock', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = OfflineSalesQueue.instance;
    queue.setConnectivityStatus(false);
    queue.setOfflineModeEnabled(true);
    final sale = QueuedSale(
      id: 'sale-offline-1',
      ownerUid: 'shop-user-1',
      createdAt: DateTime(2026, 10, 4, 12),
      items: const [
        SaleSyncItem(
          productId: 'product-1',
          productName: 'Product',
          category: 'Food',
          quantity: 3,
          originalPrice: 7000,
          sellingPrice: 10000,
        ),
      ],
      paymentType: 'cash',
      isDebtSale: false,
      username: 'Cashier',
    );

    await queue.enqueue(sale);
    await queue.enqueue(sale);

    expect(queue.pendingCount, 1);
    expect(await queue.pendingQuantities('shop-user-1'), {'product-1': 3});
    expect(await queue.containsSale('shop-user-1', 'sale-offline-1'), isTrue);

    queue.setOfflineModeEnabled(false);
    queue.setConnectivityStatus(true);
  });

  test('round-trips sale data through the persistent JSON format', () {
    final sale = QueuedSale(
      id: 'sale-offline-2',
      ownerUid: 'shop-user-2',
      createdAt: DateTime(2026, 10, 4, 12),
      items: const [
        SaleSyncItem(
          productId: 'product-2',
          productName: 'Bread',
          category: 'Bakery',
          quantity: 2,
          originalPrice: 4000,
          sellingPrice: 5000,
        ),
      ],
      paymentType: 'cash',
      isDebtSale: true,
      username: 'Cashier',
      customerId: 'customer-1',
      customerName: 'Customer',
    );

    final restored = QueuedSale.fromJson(sale.toJson());

    expect(restored.id, sale.id);
    expect(restored.ownerUid, sale.ownerUid);
    expect(restored.createdAt, sale.createdAt);
    expect(restored.total, 10000);
    expect(restored.items.single.quantity, 2);
    expect(restored.isDebtSale, isTrue);
    expect(restored.customerId, 'customer-1');
  });
}

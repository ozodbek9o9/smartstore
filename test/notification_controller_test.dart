import 'package:flutter_test/flutter_test.dart';
import 'package:smart_store/utils/notification_controller.dart';

void main() {
  final controller = NotificationController.instance;

  setUp(() {
    controller.updateCustomerAlerts([]);
    controller.updateStockAlerts([]);
    controller.resetReadState();
  });

  test('keeps stock alerts when customer alerts are refreshed', () {
    final now = DateTime.now();
    final stockAlert = NotificationAlert(
      id: 'stock_low_product',
      customerName: 'Product',
      remainingDebt: 0,
      lastActivity: now,
      customText: 'Low stock',
    );
    final customerAlert = NotificationAlert(
      id: 'customer',
      customerName: 'Customer',
      remainingDebt: 100,
      lastActivity: now,
    );

    controller.updateStockAlerts([stockAlert]);
    controller.updateCustomerAlerts([customerAlert]);

    expect(
      controller.alerts.map((alert) => alert.id),
      containsAll(['stock_low_product', 'customer']),
    );
    expect(controller.unreadCount, 2);
  });

  test('removing stock alerts does not remove customer alerts', () {
    final customerAlert = NotificationAlert(
      id: 'customer',
      customerName: 'Customer',
      remainingDebt: 100,
      lastActivity: DateTime.now(),
    );

    controller.updateStockAlerts([
      NotificationAlert(
        id: 'stock_low_product',
        customerName: 'Product',
        remainingDebt: 0,
        lastActivity: DateTime.now(),
        customText: 'Low stock',
      ),
    ]);
    controller.updateCustomerAlerts([customerAlert]);
    controller.updateStockAlerts([]);

    expect(controller.alerts.map((alert) => alert.id), ['customer']);
  });
}

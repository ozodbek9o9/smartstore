import 'package:flutter/material.dart';

class NotificationAlert {
  final String id;
  final String customerName;
  final num remainingDebt;
  final DateTime lastActivity;
  final String? customText;

  NotificationAlert({
    required this.id,
    required this.customerName,
    required this.remainingDebt,
    required this.lastActivity,
    this.customText,
  });
}

class NotificationController extends ChangeNotifier {
  static final NotificationController instance = NotificationController._();
  NotificationController._();

  List<NotificationAlert> _customerAlerts = [];
  List<NotificationAlert> _stockAlerts = [];
  bool _markedAllAsRead = false;

  List<NotificationAlert> get alerts => [..._customerAlerts, ..._stockAlerts];
  int get unreadCount => _markedAllAsRead ? 0 : alerts.length;

  void updateCustomerAlerts(List<NotificationAlert> newAlerts) {
    final updated = _updateSourceAlerts(_customerAlerts, newAlerts);
    if (identical(updated, _customerAlerts)) return;
    _customerAlerts = updated;
    _onAlertsChanged();
  }

  void updateStockAlerts(List<NotificationAlert> newAlerts) {
    final updated = _updateSourceAlerts(_stockAlerts, newAlerts);
    if (identical(updated, _stockAlerts)) return;
    _stockAlerts = updated;
    _onAlertsChanged();
  }

  List<NotificationAlert> _updateSourceAlerts(
    List<NotificationAlert> currentAlerts,
    List<NotificationAlert> newAlerts,
  ) {
    final normalized = <NotificationAlert>[];
    for (final alert in newAlerts) {
      final existing = currentAlerts
          .where((item) => item.id == alert.id)
          .firstOrNull;
      if (existing == null) {
        normalized.add(alert);
      } else if (existing.customText != alert.customText ||
          existing.customerName != alert.customerName) {
        normalized.add(alert);
      } else {
        normalized.add(existing);
      }
    }

    if (_isSameAlerts(currentAlerts, normalized)) return currentAlerts;
    return normalized;
  }

  void _onAlertsChanged() {
    if (_markedAllAsRead && alerts.isNotEmpty) {
      _markedAllAsRead = false;
    }
    notifyListeners();
  }

  bool _isSameAlerts(List<NotificationAlert> a, List<NotificationAlert> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
      if (a[i].customText != b[i].customText) return false;
      if (a[i].customerName != b[i].customerName) return false;
    }
    return true;
  }

  void markAllAsRead() {
    _markedAllAsRead = true;
    notifyListeners();
  }

  void resetReadState() {
    _markedAllAsRead = false;
    notifyListeners();
  }
}

extension on Iterable<NotificationAlert> {
  NotificationAlert? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}

import 'package:flutter/material.dart';
import '../models/pos_models.dart';
import '../repositories/pos_repository.dart';

class PosCartService extends ChangeNotifier {
  final PosRepository repository;
  final List<CartItem> _items = [];

  PosCartService({PosRepository? repository})
    : repository = repository ?? PosRepository();

  List<CartItem> get items => List.unmodifiable(_items);
  bool get hasItems => _items.isNotEmpty;
  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);
  num get subtotal => _items.fold(0, (sum, item) => sum + item.lineTotal);

  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  bool canAddItem(PosProduct product) {
    final existing = _items.firstWhere(
      (item) => item.product.id == product.id,
      orElse: () => CartItem(product: product, quantity: 0),
    );
    return existing.quantity < product.quantity;
  }

  bool addOrIncrementItem(PosProduct product) {
    if (product.quantity < 1) return false;

    final index = _items.indexWhere((item) => item.product.id == product.id);
    if (index < 0) {
      _items.add(CartItem(product: product, quantity: 1));
    } else {
      final item = _items[index];
      if (item.quantity >= product.quantity) return false;
      item.quantity += 1;
    }

    notifyListeners();
    return true;
  }

  bool canUpdateQuantity(PosProduct product, int quantity) {
    if (quantity < 1) return true;
    return quantity <= product.quantity;
  }

  bool updateQuantity(PosProduct product, int quantity) {
    final index = _items.indexWhere((item) => item.product.id == product.id);
    if (index < 0) return false;
    if (quantity < 1) {
      _items.removeAt(index);
      notifyListeners();
      return true;
    }

    final item = _items[index];
    if (quantity > product.quantity) {
      return false;
    }

    item.quantity = quantity;
    notifyListeners();
    return true;
  }

  void removeItem(PosProduct product) {
    _items.removeWhere((item) => item.product.id == product.id);
    notifyListeners();
  }

  Future<PosProduct?> scanBarcode(String barcode) async {
    return repository.fetchProductByBarcode(barcode);
  }
}

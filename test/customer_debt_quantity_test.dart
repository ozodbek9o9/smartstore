import 'package:flutter_test/flutter_test.dart';
import 'package:smart_store/models/pos_models.dart';

void main() {
  group('CustomerDebtQuantity', () {
    test('converts kilograms to grams and back', () {
      expect(
        CustomerDebtQuantity.convert(
          0.4,
          fromUnit: CustomerDebtQuantity.kilograms,
          toUnit: CustomerDebtQuantity.grams,
        ),
        400,
      );
      expect(
        CustomerDebtQuantity.convert(
          400,
          fromUnit: CustomerDebtQuantity.grams,
          toUnit: CustomerDebtQuantity.kilograms,
        ),
        0.4,
      );
    });

    test('normalizes quantities below one kilogram to grams', () {
      final quantity = CustomerDebtQuantity.normalize(
        0.4,
        unit: CustomerDebtQuantity.kilograms,
      );

      expect(quantity.value, 400);
      expect(quantity.unit, CustomerDebtQuantity.grams);
    });

    test('keeps one kilogram and larger quantities in kilograms', () {
      final quantity = CustomerDebtQuantity.normalize(
        2.3,
        unit: CustomerDebtQuantity.kilograms,
      );

      expect(quantity.value, 2.3);
      expect(quantity.unit, CustomerDebtQuantity.kilograms);
    });

    test('normalizes 1000 grams to one kilogram', () {
      final quantity = CustomerDebtQuantity.normalize(
        1000,
        unit: CustomerDebtQuantity.grams,
      );

      expect(quantity.value, 1);
      expect(quantity.unit, CustomerDebtQuantity.kilograms);
    });
  });
}

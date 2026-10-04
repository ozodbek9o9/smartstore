import 'package:flutter_test/flutter_test.dart';
import 'package:smart_store/services/sales_report_calculator.dart';

void main() {
  group('SalesReportRecord', () {
    test(
      'calculates turnover and net profit independently from sale items',
      () {
        final sale = SalesReportRecord.fromMap({
          'timestamp': DateTime(2026, 10, 4, 10),
          'total': 999999,
          'profitTotal': 999999,
          'items': [
            {
              'quantity': 1,
              'price': 20000,
              'originalPrice': 15000,
              'total': 20000,
            },
            {
              'quantity': 1,
              'price': 30000,
              'originalPrice': 22000,
              'total': 30000,
            },
            {
              'quantity': 1,
              'price': 50000,
              'originalPrice': 40000,
              'total': 50000,
            },
          ],
        });

        expect(sale?.turnover, 100000);
        expect(sale?.netProfit, 23000);
        expect(sale?.soldProducts, 3);
      },
    );

    test('ignores cancelled sales and records without a timestamp', () {
      expect(
        SalesReportRecord.fromMap({
          'timestamp': DateTime(2026, 10, 4),
          'status': 'cancelled',
          'total': 100,
        }),
        isNull,
      );
      expect(SalesReportRecord.fromMap({'total': 100}), isNull);
    });
  });

  test('builds comparable current and previous period windows', () {
    final now = DateTime(2026, 10, 4, 12);
    final window = SalesReportCalculator.windowFor(ReportPeriod.daily, now);

    expect(window.currentStart, DateTime(2026, 10, 4));
    expect(window.previousStart, DateTime(2026, 10, 3));
    expect(window.previousEnd, DateTime(2026, 10, 3, 12, 0, 0, 0, 1));
  });

  test('aggregates sold product quantity separately from order count', () {
    final totals = SalesReportCalculator.aggregate(
      [
        SalesReportRecord(
          timestamp: DateTime(2026, 10, 4, 10),
          turnover: 100000,
          netProfit: 23000,
          soldProducts: 3,
        ),
        SalesReportRecord(
          timestamp: DateTime(2026, 10, 4, 11),
          turnover: 50000,
          netProfit: 12000,
          soldProducts: 2,
        ),
      ],
      DateTime(2026, 10, 4),
      DateTime(2026, 10, 5),
    );

    expect(totals.turnover, 150000);
    expect(totals.netProfit, 35000);
    expect(totals.soldProducts, 5);
    expect(totals.orderCount, 2);
  });

  test('puts all days from day 22 through month end in week four', () {
    for (final monthCase in [
      (year: 2026, month: 2, lastDay: 28),
      (year: 2026, month: 3, lastDay: 31),
    ]) {
      final monthStart = DateTime(monthCase.year, monthCase.month);
      final nextMonthStart = DateTime(monthCase.year, monthCase.month + 1);
      final window = ReportDateWindow(
        currentStart: monthStart,
        currentEnd: nextMonthStart,
        previousStart: DateTime(monthCase.year, monthCase.month - 1),
        previousEnd: monthStart,
      );
      final sales = [
        for (var day = 21; day <= monthCase.lastDay; day++)
          SalesReportRecord(
            timestamp: DateTime(monthCase.year, monthCase.month, day),
            turnover: 100,
            netProfit: 20,
            soldProducts: 1,
          ),
      ];

      final buckets = SalesReportCalculator.bucketSales(
        ReportPeriod.monthly,
        sales,
        window,
      );

      expect(buckets, hasLength(4));
      expect(buckets[2].current.soldProducts, 1);
      expect(buckets[3].current.soldProducts, monthCase.lastDay - 21);
    }
  });

  test('returns safe percentage changes when the previous value is zero', () {
    expect(SalesReportCalculator.percentageChange(0, 0), 0);
    expect(SalesReportCalculator.percentageChange(0, 100), 100);
    expect(SalesReportCalculator.percentageChange(0, -100), -100);
    expect(SalesReportCalculator.percentageChange(200, 300), 50);
  });
}

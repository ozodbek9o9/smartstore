import 'package:cloud_firestore/cloud_firestore.dart';

enum ReportPeriod { daily, weekly, monthly, yearly }

class SalesReportRecord {
  const SalesReportRecord({
    required this.timestamp,
    required this.turnover,
    required this.netProfit,
    required this.soldProducts,
  });

  final DateTime timestamp;
  final num turnover;
  final num netProfit;
  final num soldProducts;

  static SalesReportRecord? fromMap(Map<String, dynamic> data) {
    final status = data['status']?.toString().toLowerCase();
    if (data['isDeleted'] == true ||
        const {
          'cancelled',
          'canceled',
          'void',
          'failed',
          'deleted',
        }.contains(status)) {
      return null;
    }

    final timestamp = _parseDate(
      data['timestamp'] ?? data['createdAt'] ?? data['date'],
    );
    if (timestamp == null) return null;

    final rawItems = data['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const <Map<String, dynamic>>[];

    num itemTurnover = 0;
    num itemProfit = 0;
    num itemQuantity = 0;
    for (final item in items) {
      final quantity = _number(item['quantity'], fallback: 1);
      final price = _number(
        item['price'] ?? item['sellingPrice'] ?? item['unitPrice'],
      );
      final lineTotal = item['total'] == null
          ? price * quantity
          : _number(item['total']);
      final cost = _number(item['originalPrice'] ?? item['costPrice']);
      final lineProfit = (price - cost) * quantity;
      itemTurnover += lineTotal;
      itemProfit += lineProfit;
      itemQuantity += quantity;
    }

    final storedTurnover = _firstNumber(data, [
      'total',
      'totalAmount',
      'subtotal',
    ]);
    return SalesReportRecord(
      timestamp: timestamp,
      turnover: items.isEmpty ? (storedTurnover ?? itemTurnover) : itemTurnover,
      netProfit: itemProfit,
      soldProducts: items.isEmpty
          ? _number(data['soldProducts'] ?? data['quantity'])
          : itemQuantity,
    );
  }
}

class ReportTotals {
  num turnover = 0;
  num netProfit = 0;
  num soldProducts = 0;
  int orderCount = 0;

  void add(SalesReportRecord sale) {
    turnover += sale.turnover;
    netProfit += sale.netProfit;
    soldProducts += sale.soldProducts;
    orderCount++;
  }
}

class ReportDateWindow {
  const ReportDateWindow({
    required this.currentStart,
    required this.currentEnd,
    required this.previousStart,
    required this.previousEnd,
  });

  final DateTime currentStart;
  final DateTime currentEnd;
  final DateTime previousStart;
  final DateTime previousEnd;

  bool containsCurrent(DateTime date) =>
      !date.isBefore(currentStart) && date.isBefore(currentEnd);

  bool containsPrevious(DateTime date) =>
      !date.isBefore(previousStart) && date.isBefore(previousEnd);
}

class ReportBucket {
  ReportBucket(this.label);

  final String label;
  final current = ReportTotals();
  final previous = ReportTotals();
}

class SalesReportCalculator {
  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _startOfWeek(DateTime date) {
    final day = _startOfDay(date);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static ReportDateWindow windowFor(ReportPeriod period, DateTime now) {
    late final DateTime currentStart;
    late final DateTime previousStart;
    switch (period) {
      case ReportPeriod.daily:
        currentStart = _startOfDay(now);
        previousStart = currentStart.subtract(const Duration(days: 1));
      case ReportPeriod.weekly:
        currentStart = _startOfWeek(now);
        previousStart = currentStart.subtract(const Duration(days: 7));
      case ReportPeriod.monthly:
        currentStart = DateTime(now.year, now.month);
        previousStart = DateTime(now.year, now.month - 1);
      case ReportPeriod.yearly:
        currentStart = DateTime(now.year);
        previousStart = DateTime(now.year - 1);
    }

    final currentEnd = now.add(const Duration(microseconds: 1));
    final elapsed = currentEnd.difference(currentStart);
    final previousEndCandidate = previousStart.add(elapsed);
    final previousEnd = previousEndCandidate.isAfter(currentStart)
        ? currentStart
        : previousEndCandidate;
    return ReportDateWindow(
      currentStart: currentStart,
      currentEnd: currentEnd,
      previousStart: previousStart,
      previousEnd: previousEnd,
    );
  }

  static ReportTotals aggregate(
    Iterable<SalesReportRecord> sales,
    DateTime start,
    DateTime end,
  ) {
    final totals = ReportTotals();
    for (final sale in sales) {
      if (!sale.timestamp.isBefore(start) && sale.timestamp.isBefore(end)) {
        totals.add(sale);
      }
    }
    return totals;
  }

  static List<ReportBucket> bucketSales(
    ReportPeriod period,
    Iterable<SalesReportRecord> sales,
    ReportDateWindow window,
  ) {
    final buckets = _bucketLabels(period).map(ReportBucket.new).toList();
    for (final sale in sales) {
      if (window.containsCurrent(sale.timestamp)) {
        buckets[_bucketIndex(period, sale.timestamp)].current.add(sale);
      } else if (window.containsPrevious(sale.timestamp)) {
        buckets[_bucketIndex(period, sale.timestamp)].previous.add(sale);
      }
    }
    return buckets;
  }

  static num percentageChange(num previous, num current) {
    if (previous == 0) {
      if (current == 0) return 0;
      return current > 0 ? 100 : -100;
    }
    return ((current - previous) / previous) * 100;
  }

  static List<String> _bucketLabels(ReportPeriod period) => switch (period) {
    ReportPeriod.daily => const [
      '00:00',
      '04:00',
      '08:00',
      '12:00',
      '16:00',
      '20:00',
      '23:00',
    ],
    ReportPeriod.weekly => const [
      'Dushanba',
      'Seshanba',
      'Chorshanba',
      'Payshanba',
      'Juma',
      'Shanba',
      'Yakshanba',
    ],
    ReportPeriod.monthly => const ['1-hafta', '2-hafta', '3-hafta', '4-hafta'],
    ReportPeriod.yearly => const [
      'Yan',
      'Fev',
      'Mar',
      'Apr',
      'May',
      'Iyun',
      'Iyul',
      'Avg',
      'Sen',
      'Okt',
      'Noy',
      'Dek',
    ],
  };

  static int _bucketIndex(ReportPeriod period, DateTime date) =>
      switch (period) {
        ReportPeriod.daily =>
          date.hour < 4
              ? 0
              : date.hour < 8
              ? 1
              : date.hour < 12
              ? 2
              : date.hour < 16
              ? 3
              : date.hour < 20
              ? 4
              : date.hour < 23
              ? 5
              : 6,
        ReportPeriod.weekly => date.weekday - 1,
        ReportPeriod.monthly => ((date.day - 1) ~/ 7).clamp(0, 3),
        ReportPeriod.yearly => date.month - 1,
      };
}

DateTime? _parseDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

num? _firstNumber(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data[key] != null) return _number(data[key]);
  }
  return null;
}

num _number(dynamic value, {num fallback = 0}) {
  if (value is num) return value.isFinite ? value : fallback;
  if (value is String) {
    final parsed = num.tryParse(value.replaceAll(RegExp(r'[,\s]'), ''));
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return fallback;
}

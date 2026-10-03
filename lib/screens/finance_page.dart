import 'dart:async';
import 'dart:math' as math;
import 'dart:math' show max;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:smart_store/screens/theme_controller.dart';
import '../main.dart' show SmartStoreColors;
import '../utils/tenant_firestore.dart';

enum _TimeFilter { today, thisWeek, thisYear }

class _IncomingSummary {
  final int totalQuantity;
  final int productCount;
  final num totalPurchaseValue;
  final num? totalSellingValue;
  final Map<String, _ProductAggregate> byProduct;

  _IncomingSummary({
    required this.totalQuantity,
    required this.productCount,
    required this.totalPurchaseValue,
    required this.totalSellingValue,
    required this.byProduct,
  });

  factory _IncomingSummary.empty() => _IncomingSummary(
    totalQuantity: 0,
    productCount: 0,
    totalPurchaseValue: 0,
    totalSellingValue: 0,
    byProduct: {},
  );
}

class _OutgoingSummary {
  final int totalQuantitySold;
  final int productsSoldCount;
  final num totalOriginalCost;
  final num totalSalesAmount;
  final num totalProfit;
  final Map<String, _ProductAggregate> byProduct;

  _OutgoingSummary({
    required this.totalQuantitySold,
    required this.productsSoldCount,
    required this.totalOriginalCost,
    required this.totalSalesAmount,
    required this.totalProfit,
    required this.byProduct,
  });

  factory _OutgoingSummary.empty() => _OutgoingSummary(
    totalQuantitySold: 0,
    productsSoldCount: 0,
    totalOriginalCost: 0,
    totalSalesAmount: 0,
    totalProfit: 0,
    byProduct: {},
  );
}

class _ProductAggregate {
  final String productName;
  int quantity = 0;
  num totalValue = 0;
  num totalOriginalCost = 0;
  num totalProfit = 0;
  num unitOriginalPrice = 0;

  _ProductAggregate({required this.productName, this.unitOriginalPrice = 0});
}

class _PeriodBucket {
  int incomingQty = 0;
  num incomingValue = 0;
  final incomingProductIds = <String>{};
  int outgoingQty = 0;
  num outgoingCost = 0;
  num outgoingSales = 0;
  num outgoingProfit = 0;
  final outgoingProductIds = <String>{};
}

class _ChartPoint {
  final int index;
  final DateTime date;
  final String monthLabel;
  final num incoming;
  final num outgoing;
  final num profit;
  final bool isStartOfMonth;

  _ChartPoint({
    required this.index,
    required this.date,
    required this.monthLabel,
    required this.incoming,
    required this.outgoing,
    required this.profit,
    this.isStartOfMonth = false,
  });
}

class _MMAcc {
  num incoming = 0;
  num outgoing = 0;
  num profit = 0;
}

class _WeekDayPoint {
  final DateTime day;
  final String label;
  final num incoming;
  final num outgoingCost;
  final num sales;
  final num profit;

  _WeekDayPoint({
    required this.day,
    required this.label,
    required this.incoming,
    required this.outgoingCost,
    required this.sales,
    required this.profit,
  });
}

class _ActionLogEntry {
  final DateTime timestamp;
  final String actionType;
  final String productName;
  final int quantity;
  final num originalPrice;
  final num sellingPrice;
  final num profit;
  final String user;

  _ActionLogEntry({
    required this.timestamp,
    required this.actionType,
    required this.productName,
    required this.quantity,
    required this.originalPrice,
    required this.sellingPrice,
    required this.profit,
    required this.user,
  });
}

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  _TimeFilter _selectedFilter = _TimeFilter.today;
  bool _isLoading = true;
  String? _error;

  _IncomingSummary _incoming = _IncomingSummary.empty();
  _OutgoingSummary _outgoing = _OutgoingSummary.empty();
  List<_ActionLogEntry> _actionLogs = const [];
  List<_ChartPoint> _chartPoints = const [];
  Map<String, _MMAcc> _monthBuckets = {};
  List<_WeekDayPoint> _weekDayPoints = const [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _entriesSub;
  final ScrollController _actionLogScrollController = ScrollController();
  Timer? _periodicTimer;
  DateTime _lastToday = DateTime.now();

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    _subscribeToData();
    _periodicTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final nowDay = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final lastDay = DateTime(
        _lastToday.year,
        _lastToday.month,
        _lastToday.day,
      );
      if (nowDay.isAfter(lastDay)) {
        _lastToday = DateTime.now();
        _subscribeToData();
      }
    });
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    _entriesSub?.cancel();
    _periodicTimer?.cancel();
    _actionLogScrollController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  DateTimeRange _filterRange(_TimeFilter filter) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (filter) {
      case _TimeFilter.today:
        return DateTimeRange(
          start: today,
          end: today.add(const Duration(days: 1)),
        );
      case _TimeFilter.thisWeek:
        final weekday = today.weekday;
        final weekStart = today.subtract(Duration(days: weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 7));
        return DateTimeRange(start: weekStart, end: weekEnd);
      case _TimeFilter.thisYear:
        final yearStart = DateTime(now.year, 1, 1);
        final nextYearStart = DateTime(now.year + 1, 1, 1);
        return DateTimeRange(start: yearStart, end: nextYearStart);
    }
  }

  void _subscribeToData() {
    _entriesSub?.cancel();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final graphRange = _filterRange(_selectedFilter);
    final now = DateTime.now();
    final todayS = DateTime(now.year, now.month, now.day);
    final weekday = todayS.weekday;
    final weekStart = todayS.subtract(Duration(days: weekday - 1));
    final yearStart = DateTime(now.year, 1, 1);
    DateTime finalStart = graphRange.start;
    if (finalStart.isAfter(weekStart)) finalStart = weekStart;
    if (finalStart.isAfter(yearStart)) finalStart = yearStart;
    final range = DateTimeRange(start: finalStart, end: graphRange.end);

    DateTimeRange uiRangeStats = graphRange;
    if (_selectedFilter == _TimeFilter.thisYear) {
      final monthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart = DateTime(now.year, now.month + 1, 1);
      uiRangeStats = DateTimeRange(start: monthStart, end: nextMonthStart);
    }

    _entriesSub = TenantFirestore.inventoryEntries
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            try {
              final filteredDocs = snapshot.docs.where((doc) {
                final ts = doc.data()['timestamp'] as Timestamp?;
                if (ts == null) return false;
                final time = ts.toDate();
                return !time.isBefore(range.start) && !time.isAfter(range.end);
              }).toList();

              _processEntries(
                filteredDocs,
                uiRange: uiRangeStats,
                graphRange: graphRange,
              );
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _error = null;
                });
              }
            } catch (e) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _error = e.toString();
                });
              }
            }
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _error = error.toString();
            });
          },
        );
  }

  String _dayKey(DateTime d) {
    final y = d.year.toString();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _weekKey(DateTime d) {
    final weekday = d.weekday;
    final weekStart = DateTime(
      d.year,
      d.month,
      d.day,
    ).subtract(Duration(days: weekday - 1));
    return 'W-${_dayKey(weekStart)}';
  }

  Future<void> _savePeriodSummaries(
    Map<String, _PeriodBucket> dayBuckets,
    Map<String, _PeriodBucket> weekBuckets,
  ) async {
    try {
      final batch = TenantFirestore.inventoryEntries.firestore.batch();
      for (final entry in dayBuckets.entries) {
        final b = entry.value;
        final doc = TenantFirestore.dailySummaries.doc(entry.key);
        batch.set(doc, {
          'date': entry.key,
          'incomingQty': b.incomingQty,
          'incomingValue': b.incomingValue,
          'incomingProducts': b.incomingProductIds.length,
          'outgoingQty': b.outgoingQty,
          'outgoingCost': b.outgoingCost,
          'outgoingSales': b.outgoingSales,
          'outgoingProfit': b.outgoingProfit,
          'outgoingProducts': b.outgoingProductIds.length,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      for (final entry in weekBuckets.entries) {
        final b = entry.value;
        final doc = TenantFirestore.weeklySummaries.doc(entry.key);
        batch.set(doc, {
          'weekKey': entry.key,
          'incomingQty': b.incomingQty,
          'incomingValue': b.incomingValue,
          'incomingProducts': b.incomingProductIds.length,
          'outgoingQty': b.outgoingQty,
          'outgoingCost': b.outgoingCost,
          'outgoingSales': b.outgoingSales,
          'outgoingProfit': b.outgoingProfit,
          'outgoingProducts': b.outgoingProductIds.length,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (e) {
      // ignore: avoid_print
      print('Failed to save period summaries: $e');
    }
  }

  void _processEntries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required DateTimeRange uiRange,
    required DateTimeRange graphRange,
  }) {
    final incomingByProduct = <String, _ProductAggregate>{};
    final outgoingByProduct = <String, _ProductAggregate>{};
    final logs = <_ActionLogEntry>[];
    final dayBuckets = <String, _PeriodBucket>{};
    final weekBuckets = <String, _PeriodBucket>{};
    final now = DateTime.now();
    final monthBuckets = <String, _MMAcc>{};
    final monthLabels = <String>[
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
    ];
    final monthKeysOrdered = <String>[];
    final startMonth = DateTime(now.year, now.month - 3, 1);
    for (int i = -3; i <= 2; i++) {
      final m = DateTime(now.year, now.month + i, 1);
      final mk = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      monthKeysOrdered.add(mk);
      monthBuckets[mk] = _MMAcc();
    }

    int incomingQty = 0;
    num incomingValue = 0;
    num incomingSellingValue = 0;
    final incomingProductIds = <String>{};

    int outgoingQty = 0;
    final outgoingProductIds = <String>{};
    num outgoingCost = 0;
    num outgoingSales = 0;
    num outgoingProfit = 0;

    num parseNum(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v;
      final r = num.tryParse(v.toString());
      if (r == null || r.isNaN || r.isInfinite) return 0;
      return r;
    }

    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) {
        if (v.isNaN || v.isInfinite) return 0;
        return v.toInt();
      }
      final r = num.tryParse(v.toString());
      if (r == null || r.isNaN || r.isInfinite) return 0;
      return r.toInt();
    }

    DateTime parseDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) {
        final r = DateTime.tryParse(v);
        if (r != null) return r;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    String monthKey(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}';

    for (final doc in docs) {
      final data = doc.data();
      final type = (data['type'] as String?) ?? '';
      final productId = (data['productId'] as String?) ?? doc.id;
      final productName = (data['productName'] as String?) ?? '';
      final quantity = parseInt(data['quantity']);
      final originalPrice = parseNum(data['originalPrice']);
      final sellingPrice = parseNum(data['sellingPrice']);
      final ts = parseDate(data['timestamp']);
      final user = (data['user'] as String?) ?? 'Unknown';
      final isSale = type == 'outgoing';
      final isAdjustment = type == 'adjustment_outgoing';
      final inUiRange = !ts.isBefore(uiRange.start) && !ts.isAfter(uiRange.end);

      final dk = _dayKey(ts);
      final wk = _weekKey(ts);
      final dayBucket = dayBuckets.putIfAbsent(dk, () => _PeriodBucket());
      final weekBucket = weekBuckets.putIfAbsent(wk, () => _PeriodBucket());
      final mk = monthKey(ts);
      final mBucket = monthBuckets[mk];

      if (type == 'incoming') {
        final totalValue = parseNum(data['totalValue']);
        final safeQty = quantity;
        final safeValue = totalValue;
        final safeSellingValue = sellingPrice * safeQty;
        if (inUiRange) {
          incomingQty += safeQty;
          incomingValue += safeValue;
          incomingSellingValue += safeSellingValue;
          incomingProductIds.add(productId);
        }

        dayBucket.incomingQty += safeQty;
        dayBucket.incomingValue += safeValue;
        dayBucket.incomingProductIds.add(productId);
        weekBucket.incomingQty += safeQty;
        weekBucket.incomingValue += safeValue;
        weekBucket.incomingProductIds.add(productId);
        if (mBucket != null) {
          mBucket.incoming += safeValue;
        }

        if (inUiRange) {
          final agg = incomingByProduct.putIfAbsent(
            productId,
            () => _ProductAggregate(
              productName: productName,
              unitOriginalPrice: originalPrice,
            ),
          );
          agg.quantity += safeQty;
          agg.totalValue += safeSellingValue;
          agg.totalOriginalCost += safeValue;
          if (originalPrice > 0) agg.unitOriginalPrice = originalPrice;
        }

        logs.add(
          _ActionLogEntry(
            timestamp: ts,
            actionType: 'incoming',
            productName: productName,
            quantity: safeQty,
            originalPrice: originalPrice,
            sellingPrice: sellingPrice,
            profit: 0,
            user: user,
          ),
        );
      } else if (isSale || isAdjustment) {
        final totalCost = parseNum(data['totalCostValue']);
        final totalSale = isSale ? parseNum(data['totalSaleValue']) : 0;
        final totalProfit = isSale ? parseNum(data['totalProfit']) : 0;
        final safeQty = quantity;
        final safeCost = totalCost;
        final safeSale = totalSale;
        final sign = 1;
        final signedCost = sign * safeCost;
        final signedSale = sign * safeSale;
        final signedProfit = sign * totalProfit;

        if (inUiRange) {
          outgoingQty += safeQty;
          outgoingCost += signedCost;
          outgoingSales += signedSale;
          outgoingProfit += signedProfit;
          if (isSale) outgoingProductIds.add(productId);
        }

        dayBucket.outgoingQty += safeQty;
        dayBucket.outgoingCost += safeCost;
        dayBucket.outgoingSales += safeSale;
        dayBucket.outgoingProfit += totalProfit;
        dayBucket.outgoingProductIds.add(productId);
        weekBucket.outgoingQty += safeQty;
        weekBucket.outgoingCost += safeCost;
        weekBucket.outgoingSales += safeSale;
        weekBucket.outgoingProfit += totalProfit;
        weekBucket.outgoingProductIds.add(productId);
        if (mBucket != null) {
          mBucket.outgoing += safeSale;
          mBucket.profit += totalProfit;
        }

        if (inUiRange) {
          final agg = outgoingByProduct.putIfAbsent(
            productId,
            () => _ProductAggregate(
              productName: productName,
              unitOriginalPrice: originalPrice,
            ),
          );
          agg.quantity += safeQty;
          agg.totalValue += signedSale;
          agg.totalOriginalCost += signedCost;
          agg.totalProfit += signedProfit;
          if (originalPrice > 0) agg.unitOriginalPrice = originalPrice;
        }

        logs.add(
          _ActionLogEntry(
            timestamp: ts,
            actionType: 'outgoing',
            productName: productName,
            quantity: safeQty,
            originalPrice: originalPrice,
            sellingPrice: sellingPrice,
            profit: totalProfit,
            user: user,
          ),
        );
      }
    }

    final chartPoints = <_ChartPoint>[];
    DateTime currentD = startMonth;
    int index = 0;
    while (!currentD.isAfter(now)) {
      final dk = _dayKey(currentD);
      final b = dayBuckets[dk];
      final isStartOfMonth = currentD.day == 1 || index == 0;

      chartPoints.add(
        _ChartPoint(
          index: index,
          date: currentD,
          monthLabel: monthLabels[currentD.month - 1],
          incoming: b?.incomingValue ?? 0,
          outgoing: b?.outgoingSales ?? 0,
          profit: b?.outgoingProfit ?? 0,
          isStartOfMonth: isStartOfMonth,
        ),
      );
      currentD = currentD.add(const Duration(days: 1));
      index++;
    }

    final weekDayLabels = <String>['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];
    final nowW = DateTime.now();
    final todayW = DateTime(nowW.year, nowW.month, nowW.day);
    final weekdayW = todayW.weekday;
    final weekStartW = todayW.subtract(Duration(days: weekdayW - 1));
    final weekDayPoints = <_WeekDayPoint>[];
    for (int i = 0; i < 7; i++) {
      final d = weekStartW.add(Duration(days: i));
      final dk = _dayKey(d);
      final bucket = dayBuckets[dk];
      weekDayPoints.add(
        _WeekDayPoint(
          day: d,
          label: weekDayLabels[d.weekday - 1],
          incoming: bucket?.incomingValue ?? 0,
          outgoingCost: bucket?.outgoingCost ?? 0,
          sales: bucket?.outgoingSales ?? 0,
          profit: bucket?.outgoingProfit ?? 0,
        ),
      );
    }

    _savePeriodSummaries(dayBuckets, weekBuckets);

    if (mounted) {
      setState(() {
        _incoming = _IncomingSummary(
          totalQuantity: incomingQty,
          productCount: incomingProductIds.length,
          totalPurchaseValue: incomingValue,
          totalSellingValue: incomingSellingValue,
          byProduct: incomingByProduct,
        );
        _outgoing = _OutgoingSummary(
          totalQuantitySold: outgoingQty,
          productsSoldCount: outgoingProductIds.length,
          totalOriginalCost: outgoingCost,
          totalSalesAmount: outgoingSales,
          totalProfit: outgoingProfit,
          byProduct: outgoingByProduct,
        );
        _actionLogs = List.unmodifiable(logs);
        _chartPoints = List.unmodifiable(chartPoints);
        _monthBuckets = monthBuckets;
        _weekDayPoints = List.unmodifiable(weekDayPoints);
      });
    }
  }

  String _t(String key, String fallback, [List<String>? args]) {
    String text = key.tr();
    if (text == key || text.isEmpty) text = fallback;
    if (args != null) {
      for (int i = 0; i < args.length; i++) {
        text = text.replaceFirst('{$i}', args[i]);
      }
    }
    return text;
  }

  String _formatMoney(num amount) {
    final intVal = amount.round();
    final str = intVal.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(' ');
      }
      buffer.write(str[i]);
    }
    return '${intVal < 0 ? "-" : ""}${buffer.toString()} ${_t('common.currency', "so'm")}';
  }

  String _formatQuantity(int qty) {
    return '$qty ${_t('common.pieces', 'dona')}';
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d.$m.$y';
  }

  @override
  Widget build(BuildContext context) {
    final _ = context.locale; // Subscribe to EasyLocalization locale changes
    final isDark = ThemeController.instance.isDarkMode;
    final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
    final borderColor = isDark
        ? SmartStoreColors.darkDivider
        : const Color(0xFFE2E8F0);
    final textPrimary = isDark
        ? SmartStoreColors.darkTextPrimary
        : SmartStoreColors.lightTextPrimary;
    final textSecondary = isDark
        ? SmartStoreColors.darkTextSecondary
        : SmartStoreColors.lightTextSecondary;
    final textMuted = isDark
        ? SmartStoreColors.darkTextMuted
        : SmartStoreColors.lightTextMuted;
    final pageBg = isDark
        ? SmartStoreColors.darkBackground
        : const Color(0xFFF0F4FF);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: pageBg,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _buildFilterBar(
                  isDark,
                  borderColor,
                  textPrimary,
                  textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                _buildLoading(textMuted)
              else if (_error != null)
                _buildError(_error!, textSecondary)
              else ...[
                _buildSummaryCards(
                  cardBg,
                  borderColor,
                  textPrimary,
                  textSecondary,
                  textMuted,
                  isDark,
                ),
                const SizedBox(height: 20),
                _buildMiddleSection(
                  cardBg,
                  borderColor,
                  textPrimary,
                  textSecondary,
                  textMuted,
                  isDark,
                ),
                const SizedBox(height: 20),
                _buildTopProductTables(
                  cardBg,
                  borderColor,
                  textPrimary,
                  textSecondary,
                  textMuted,
                  isDark,
                ),
                const SizedBox(height: 20),
                _buildActionLogTable(
                  cardBg,
                  borderColor,
                  textPrimary,
                  textSecondary,
                  textMuted,
                  isDark,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(Color textMuted) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _t('finance.loading', 'Loading financial data...'),
              style: TextStyle(color: textMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String msg, Color textSecondary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: SmartStoreColors.danger,
            ),
            const SizedBox(height: 12),
            Text(
              _t('finance.error_loading', 'Failed to load data'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(msg, style: TextStyle(fontSize: 12, color: textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(
    bool isDark,
    Color borderColor,
    Color textPrimary,
    Color textSecondary,
  ) {
    final filters = <_TimeFilter, String>{
      _TimeFilter.today: _t('finance.filter.today', 'Bugun'),
      _TimeFilter.thisWeek: _t('finance.filter.this_week', 'Hafta'),
      _TimeFilter.thisYear: _t('finance.filter.this_year', 'Shu yil'),
    };

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? SmartStoreColors.darkSurfaceVariant
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: filters.entries.map((entry) {
          final isSelected = _selectedFilter == entry.key;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedFilter = entry.key);
              _subscribeToData();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF2563EB)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? textSecondary : const Color(0xFF475569)),
                  letterSpacing: -0.1,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummaryCards(
    Color cardBg,
    Color borderColor,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
    bool isDark,
  ) {
    const double cardWidth = 280;

    final cards = [
      SizedBox(
        width: cardWidth,
        child: _buildCard(
          cardBg: cardBg,
          borderColor: borderColor,
          icon: Icons.download_rounded,
          iconBg: const Color(0xFF3B82F6),
          iconGradient: const [Color(0xFF2563EB), Color(0xFF3B82F6)],
          title: _t('finance.card.incoming', 'Omborga kirim'),
          subtitle: _formatQuantity(_incoming.totalQuantity),
          value: _formatMoney(_incoming.totalSellingValue ?? 0),
          subLabel:
              '${_incoming.productCount} ${_t('finance.products', 'mahsulot')}',
          subLabelColor: const Color(0xFF2563EB),
          dotColor: const Color(0xFF2563EB),
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          textMuted: textMuted,
        ),
      ),
      SizedBox(
        width: cardWidth,
        child: _buildCard(
          cardBg: cardBg,
          borderColor: borderColor,
          icon: Icons.inventory_2_rounded,
          iconBg: const Color(0xFFEF4444),
          iconGradient: const [Color(0xFFDC2626), Color(0xFFEF4444)],
          title: _t('finance.card.total_cost', 'Xarajat (asl narx)'),
          subtitle: _t('finance.card.total_cost_sub', 'Omborga kirish'),
          value: _formatMoney(_incoming.totalPurchaseValue),
          subLabel:
              '${_incoming.productCount} ${_t('finance.products', 'mahsulot')}',
          subLabelColor: const Color(0xFFDC2626),
          dotColor: const Color(0xFFEF4444),
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          textMuted: textMuted,
        ),
      ),
      SizedBox(
        width: cardWidth,
        child: _buildCard(
          cardBg: cardBg,
          borderColor: borderColor,
          icon: Icons.shopping_cart_checkout_rounded,
          iconBg: const Color(0xFFF59E0B),
          iconGradient: const [Color(0xFFD97706), Color(0xFFF59E0B)],
          title: _t('finance.card.total_sales', 'Sotuv summasi'),
          subtitle: _t('finance.total_sales_sub', 'Jami sotilganlar'),
          value: _formatMoney(_outgoing.totalSalesAmount),
          subLabel:
              '${_outgoing.productsSoldCount} ${_t('finance.products', 'mahsulot')}',
          subLabelColor: const Color(0xFFD97706),
          dotColor: const Color(0xFFF59E0B),
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          textMuted: textMuted,
        ),
      ),
      SizedBox(
        width: cardWidth,
        child: Builder(
          builder: (context) {
            final isProfit = _outgoing.totalProfit >= 0;
            final profitColor = isProfit
                ? const Color(0xFF10B981)
                : const Color(0xFFEF4444);
            final profitBg = isProfit
                ? const [Color(0xFF059669), Color(0xFF10B981)]
                : const [Color(0xFFDC2626), Color(0xFFEF4444)];
            return _buildCard(
              cardBg: cardBg,
              borderColor: borderColor,
              icon: Icons.monetization_on_rounded,
              iconBg: profitColor,
              iconGradient: profitBg,
              title: _t('finance.card.total_profit', 'Jami foyda'),
              subtitle: _t('finance.profit_sub', 'Sotish narxi - Asl narx'),
              value: _formatMoney(_outgoing.totalProfit),
              subLabel: _outgoing.totalSalesAmount > 0
                  ? '${((_outgoing.totalProfit / _outgoing.totalSalesAmount) * 100).toStringAsFixed(1)}%'
                  : '0%',
              subLabelColor: profitColor,
              dotColor: profitColor,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              textMuted: textMuted,
            );
          },
        ),
      ),
    ];

    const double cardW = 280;
    const double minGap = 16;
    const double totalMinWidth = cardW * 4 + minGap * 3;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= totalMinWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cards[0],
              const Spacer(),
              cards[1],
              const Spacer(),
              cards[2],
              const Spacer(),
              cards[3],
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cards[0],
              const SizedBox(width: minGap),
              cards[1],
              const SizedBox(width: minGap),
              cards[2],
              const SizedBox(width: minGap),
              cards[3],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard({
    required Color cardBg,
    required Color borderColor,
    required IconData icon,
    required Color iconBg,
    required List<Color> iconGradient,
    required String title,
    required String subtitle,
    required String value,
    required String subLabel,
    required Color subLabelColor,
    required Color dotColor,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: iconGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: iconBg.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: textMuted,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: textSecondary,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: subLabelColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleSection(
    Color cardBg,
    Color borderColor,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
    bool isDark,
  ) {
    if (_selectedFilter == _TimeFilter.thisYear) {
      return _buildMonthlyLineChart(
        cardBg: cardBg,
        borderColor: borderColor,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textMuted: textMuted,
        isDark: isDark,
      );
    }
    if (_selectedFilter == _TimeFilter.thisWeek) {
      return _buildWeekly3DBarChart(
        cardBg: cardBg,
        borderColor: borderColor,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textMuted: textMuted,
        isDark: isDark,
      );
    }
    return _buildProfitCard(
      cardBg: cardBg,
      borderColor: borderColor,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      isDark: isDark,
    );
  }

  String _formatShort(num v) {
    final n = v.abs().toDouble();
    if (n >= 1e9) {
      return '${(v / 1e9).toStringAsFixed(v.abs() % 1e9 == 0 ? 0 : 1)}mlrd';
    }
    if (n >= 1e6) {
      return '${(v / 1e6).toStringAsFixed(v.abs() % 1e6 == 0 ? 0 : 1)}mln';
    }
    if (n >= 1e3) {
      return '${(v / 1e3).toStringAsFixed(v.abs() % 1e3 == 0 ? 0 : 0)}k';
    }
    return v.toInt().toString();
  }

  Widget _buildMonthlyLineChart({
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required bool isDark,
  }) {
    final cIncoming = const Color(0xFF2563EB);
    final cOutgoing = const Color(0xFFF59E0B);
    final cProfit = const Color(0xFF10B981);

    if (_chartPoints.isEmpty) {
      return _buildCardContainer(
        cardBg: cardBg,
        borderColor: borderColor,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('finance.chart.title_half_year', '6 oylik statistika'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 40),
            Center(
              child: Text(
                _t('finance.chart.no_data', 'Grafik ma\'lumotlari yo\'q'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    num minV = 0;
    num maxV = 1;
    for (final p in _chartPoints) {
      for (final v in [p.incoming, p.outgoing, p.profit]) {
        final d = v.toDouble();
        if (d.isNaN || d.isInfinite) continue;
        if (d < minV) minV = d;
        if (d > maxV) maxV = d;
      }
    }
    final hasNegative = minV < 0;
    final range = (maxV - minV).toDouble();
    final roughStep = range <= 0 ? 1 : range / 4;
    final pow10 = math.pow(
      10,
      (math.log(roughStep <= 0 ? 1 : roughStep) / math.ln10).floor(),
    );
    final normalizedStep = roughStep / pow10;
    final niceStep = normalizedStep <= 1
        ? 1
        : normalizedStep <= 2
        ? 2
        : normalizedStep <= 5
        ? 5
        : 10;
    final step = (niceStep * pow10).toDouble();
    final maxY = hasNegative
        ? (maxV / step).ceilToDouble() * step
        : max((maxV / step).ceilToDouble() * step, step);
    final minY = hasNegative ? (minV / step).floorToDouble() * step : 0.0;

    final yTicks = <double>[];
    if (hasNegative) {
      for (double t = minY; t <= maxY + step * 0.001; t += step) {
        yTicks.add(double.parse(t.toStringAsFixed(8)));
      }
    } else {
      for (double t = 0; t <= maxY + step * 0.001; t += step) {
        yTicks.add(double.parse(t.toStringAsFixed(8)));
      }
    }

    double clampY(num v) {
      final d = v.toDouble();
      if (d.isNaN || d.isInfinite) return 0;
      return d;
    }

    final spotsIncoming = <FlSpot>[];
    final spotsOutgoing = <FlSpot>[];
    final spotsProfit = <FlSpot>[];
    final monthFullTitles = <String>[
      _t('finance.month.1', 'Yanvar'),
      _t('finance.month.2', 'Fevral'),
      _t('finance.month.3', 'Mart'),
      _t('finance.month.4', 'Aprel'),
      _t('finance.month.5', 'May'),
      _t('finance.month.6', 'Iyun'),
      _t('finance.month.7', 'Iyul'),
      _t('finance.month.8', 'Avgust'),
      _t('finance.month.9', 'Sentyabr'),
      _t('finance.month.10', 'Oktyabr'),
      _t('finance.month.11', 'Noyabr'),
      _t('finance.month.12', 'Dekabr'),
    ];
    final now = DateTime.now();
    final startMonth = DateTime(now.year, now.month - 3, 1);
    final endMonth = DateTime(now.year, now.month + 3, 0);
    final totalDays = endMonth.difference(startMonth).inDays;
    for (int i = 0; i < _chartPoints.length; i++) {
      final p = _chartPoints[i];
      final x = i.toDouble();
      spotsIncoming.add(FlSpot(x, clampY(p.incoming)));
      spotsOutgoing.add(FlSpot(x, clampY(p.outgoing)));
      spotsProfit.add(FlSpot(x, clampY(p.profit)));
    }

    LineChartBarData line({
      required String key,
      required List<FlSpot> spots,
      required Color color,
    }) {
      return LineChartBarData(
        show: true,
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.45,
        preventCurveOverShooting: true,
        preventCurveOvershootingThreshold: 1.0,
        color: color,
        barWidth: 4,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: false,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 5,
            color: color,
            strokeWidth: 2.5,
            strokeColor: cardBg,
          ),
        ),
        belowBarData: BarAreaData(show: false),
      );
    }

    final titlesStyle = TextStyle(
      fontSize: 10,
      color: textMuted,
      fontWeight: FontWeight.w600,
    );

    return _buildCardContainer(
      cardBg: cardBg,
      borderColor: borderColor,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _t('finance.chart.title_half_year', '6 oylik statistika'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _buildChartLegend(
                    cIncoming,
                    _t('finance.chart.incoming', 'Omborga kirish'),
                    textSecondary,
                  ),
                  _buildChartLegend(
                    cOutgoing,
                    _t('finance.chart.outgoing', 'Ombordan chiqish'),
                    textSecondary,
                  ),
                  _buildChartLegend(
                    cProfit,
                    _t('finance.chart.profit', 'Jami foyda'),
                    textSecondary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 380,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color:
                        (isDark
                                ? SmartStoreColors.darkDivider
                                : const Color(0xFFE5E7EB))
                            .withValues(alpha: 0.5),
                    strokeWidth: 0.8,
                  ),
                  getDrawingVerticalLine: (v) => FlLine(
                    color:
                        (isDark
                                ? SmartStoreColors.darkDivider
                                : const Color(0xFFE5E7EB))
                            .withValues(alpha: 0.25),
                    strokeWidth: 0.8,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: textMuted.withValues(alpha: 0.4),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      interval: max(step, 1),
                      getTitlesWidget: (value, meta) {
                        final snap = (value / step).roundToDouble() * step;
                        final matches = yTicks.any(
                          (t) => (t - snap).abs() < step * 0.01,
                        );
                        if (!matches) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            _formatShort(value),
                            style: titlesStyle,
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i > totalDays) {
                          return const SizedBox.shrink();
                        }

                        final d = DateTime(
                          startMonth.year,
                          startMonth.month,
                          startMonth.day + i,
                        );
                        if (d.day != 1 && i != 0) {
                          return const SizedBox.shrink();
                        }

                        final shortMonthNames = [
                          _t('finance.month.short.1', 'Yan'),
                          _t('finance.month.short.2', 'Fev'),
                          _t('finance.month.short.3', 'Mar'),
                          _t('finance.month.short.4', 'Apr'),
                          _t('finance.month.short.5', 'May'),
                          _t('finance.month.short.6', 'Iyn'),
                          _t('finance.month.short.7', 'Iyl'),
                          _t('finance.month.short.8', 'Avg'),
                          _t('finance.month.short.9', 'Sen'),
                          _t('finance.month.short.10', 'Okt'),
                          _t('finance.month.short.11', 'Noy'),
                          _t('finance.month.short.12', 'Dek'),
                        ];

                        return GestureDetector(
                          onTap: () {
                            final mk =
                                '${d.year}-${d.month.toString().padLeft(2, '0')}';
                            final mb = _monthBuckets[mk] ?? _MMAcc();
                            final monthName = monthFullTitles[d.month - 1];
                            _showStatsModal(
                              incoming: mb.incoming,
                              outgoing: mb.outgoing,
                              profit: mb.profit,
                              title: monthName,
                              subtitle: _t(
                                'finance.modal_month_subtitle',
                                "Oy bo'yicha statistika",
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              shortMonthNames[d.month - 1],
                              style: titlesStyle.copyWith(
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: totalDays.toDouble(),
                minY: minY,
                maxY: maxY,
                lineBarsData: [
                  line(key: 'inc', spots: spotsIncoming, color: cIncoming),
                  line(key: 'out', spots: spotsOutgoing, color: cOutgoing),
                  line(key: 'prf', spots: spotsProfit, color: cProfit),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
                    if (event is FlLongPressEnd || event is FlTapUpEvent) {
                      final spots = response?.lineBarSpots;
                      if (spots == null || spots.isEmpty) return;
                      final first = spots.first;
                      int idx = first.spotIndex;
                      if (idx < 0 || idx >= _chartPoints.length) {
                        final roundIdx = first.x.round();
                        if (roundIdx >= 0 && roundIdx < _chartPoints.length) {
                          idx = roundIdx;
                        }
                      }
                      if (idx < 0 || idx >= _chartPoints.length) return;
                      final p = _chartPoints[idx];
                      final dateStr =
                          '${p.date.day.toString().padLeft(2, '0')}.${p.date.month.toString().padLeft(2, '0')}.${p.date.year}';
                      _showStatsModal(
                        incoming: p.incoming,
                        outgoing: p.outgoing,
                        profit: p.profit,
                        title: dateStr,
                        subtitle: _t(
                          'finance.modal_day_subtitle',
                          'Kun bo\'yicha statistika',
                        ),
                      );
                    }
                  },
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => isDark
                        ? SmartStoreColors.darkSurfaceVariant
                        : const Color(0xFF0F172A),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    tooltipPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    tooltipRoundedRadius: 10,
                    tooltipMargin: 12,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        int idx = spot.spotIndex;
                        if (idx < 0 || idx >= _chartPoints.length) {
                          final roundIdx = spot.x.round();
                          if (roundIdx >= 0 && roundIdx < _chartPoints.length) {
                            idx = roundIdx;
                          }
                        }
                        if (idx < 0 || idx >= _chartPoints.length) {
                          return null;
                        }
                        final p = _chartPoints[idx];
                        final monthName =
                            '${p.date.day.toString().padLeft(2, '0')}.${p.date.month.toString().padLeft(2, '0')}.${p.date.year}';
                        return LineTooltipItem(
                          '$monthName\n${_formatMoney(spot.y)}',
                          TextStyle(
                            color: spot.barIndex == 0
                                ? cIncoming
                                : spot.barIndex == 1
                                ? cOutgoing
                                : cProfit,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegend(Color color, String label, Color textSecondary) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
      ],
    );
  }

  void _showStatsModal({
    required num incoming,
    required num outgoing,
    required num profit,
    required String title,
    required String subtitle,
  }) {
    final isDark = ThemeController.instance.isDarkMode;
    final cardBg = isDark ? SmartStoreColors.darkSurface : Colors.white;
    final borderColor = isDark
        ? SmartStoreColors.darkDivider
        : const Color(0xFFE2E8F0);
    final textPrimary = isDark
        ? SmartStoreColors.darkTextPrimary
        : SmartStoreColors.lightTextPrimary;
    final textSecondary = isDark
        ? SmartStoreColors.darkTextSecondary
        : SmartStoreColors.lightTextSecondary;
    final textMuted = isDark
        ? SmartStoreColors.darkTextMuted
        : SmartStoreColors.lightTextMuted;
    final isProfit = profit >= 0;
    const cIncoming = Color(0xFF2563EB);
    const cOutgoing = Color(0xFFF59E0B);
    const cProfit = Color(0xFF10B981);
    final profitColor = isProfit ? cProfit : const Color(0xFFEF4444);

    Widget statRow({
      required Color color,
      required String label,
      required num amount,
      Color? amountColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.25 : 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatMoney(amount),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: amountColor ?? textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark
                            ? SmartStoreColors.darkSurfaceVariant
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: textSecondary,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              statRow(
                color: cIncoming,
                label: _t(
                  'finance.modal_incoming',
                  'Omborga kirim (sotish narxi)',
                ),
                amount: incoming,
              ),
              const SizedBox(height: 10),
              statRow(
                color: cOutgoing,
                label: _t('finance.modal_outgoing', 'Sotuv summasi (chiqim)'),
                amount: outgoing,
              ),
              const SizedBox(height: 10),
              statRow(
                color: profitColor,
                label: _t(
                  'finance.modal_profit',
                  isProfit ? 'Jami foyda' : 'Jami zarar',
                ),
                amount: profit,
                amountColor: profitColor,
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    _t('common.close', 'Yopish'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardContainer({
    required Color cardBg,
    required Color borderColor,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 18, 20, 18),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  Widget _buildWeekly3DBarChart({
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required bool isDark,
  }) {
    const cIncoming = Color(0xFF2563EB);
    const cOutCost = Color(0xFFDC2626);
    const cSales = Color(0xFFF59E0B);
    const cProfit = Color(0xFF10B981);

    if (_weekDayPoints.isEmpty) {
      return _buildCardContainer(
        cardBg: cardBg,
        borderColor: borderColor,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('finance.weekly_chart.title', 'Haftalik statistika (Du-Ya)'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 40),
            Center(
              child: Text(
                _t('finance.chart.no_data', 'Grafik ma\'lumotlari yo\'q'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    num maxAbsY = 1;
    for (final p in _weekDayPoints) {
      for (final v in [p.incoming, p.outgoingCost, p.sales, p.profit]) {
        final a = v.abs().toDouble();
        if (!a.isNaN && !a.isInfinite && a > maxAbsY) maxAbsY = a;
      }
    }
    final roughStep = maxAbsY / 4;
    final pow10 = math.pow(
      10,
      (math.log(roughStep <= 0 ? 1 : roughStep) / math.ln10).floor(),
    );
    final normalizedStep = roughStep / pow10;
    final niceStep = normalizedStep <= 1
        ? 1
        : normalizedStep <= 2
        ? 2
        : normalizedStep <= 5
        ? 5
        : 10;
    final step = (niceStep * pow10).toDouble();
    final maxY = (maxAbsY / step).ceilToDouble() * step;

    List<BarChartGroupData> barGroups = [];
    for (int dayIdx = 0; dayIdx < _weekDayPoints.length; dayIdx++) {
      final p = _weekDayPoints[dayIdx];
      final rods = <BarChartRodData>[
        BarChartRodData(
          toY: p.incoming.toDouble(),
          width: 10,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF60A5FA), Color(0xFF2563EB), Color(0xFF1D4ED8)],
          ),
          borderSide: BorderSide(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        BarChartRodData(
          toY: p.outgoingCost.toDouble(),
          width: 10,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFCA5A5), Color(0xFFDC2626), Color(0xFFB91C1C)],
          ),
          borderSide: BorderSide(
            color: const Color(0xFF7F1D1D).withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        BarChartRodData(
          toY: p.sales.toDouble(),
          width: 10,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFCD34D), Color(0xFFF59E0B), Color(0xFFB45309)],
          ),
          borderSide: BorderSide(
            color: const Color(0xFF78350F).withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        BarChartRodData(
          toY: p.profit.toDouble(),
          width: 10,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: p.profit >= 0
                ? const [
                    Color(0xFF6EE7B7),
                    Color(0xFF10B981),
                    Color(0xFF059669),
                  ]
                : const [
                    Color(0xFFFCA5A5),
                    Color(0xFFEF4444),
                    Color(0xFFB91C1C),
                  ],
          ),
          borderSide: BorderSide(
            color:
                (p.profit >= 0
                        ? const Color(0xFF064E3B)
                        : const Color(0xFF7F1D1D))
                    .withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
      ];
      barGroups.add(
        BarChartGroupData(
          x: dayIdx,
          barsSpace: 2,
          groupVertically: false,
          barRods: rods,
        ),
      );
    }

    final titlesStyle = TextStyle(
      fontSize: 10.5,
      color: textMuted,
      fontWeight: FontWeight.w600,
    );
    final weekdayFull = <String>[
      _t('finance.day.mon', 'Dushanba'),
      _t('finance.day.tue', 'Seshanba'),
      _t('finance.day.wed', 'Chorshanba'),
      _t('finance.day.thu', 'Payshanba'),
      _t('finance.day.fri', 'Juma'),
      _t('finance.day.sat', 'Shanba'),
      _t('finance.day.sun', 'Yakshanba'),
    ];

    return _buildCardContainer(
      cardBg: cardBg,
      borderColor: borderColor,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _t('finance.weekly_chart.title', 'Haftalik statistika (Du-Ya)'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _buildChartLegend(
                    cIncoming,
                    _t('finance.weekly.incoming', 'Kirim (ombor)'),
                    textSecondary,
                  ),
                  _buildChartLegend(
                    cOutCost,
                    _t('finance.weekly.out_cost', 'Chiqim (xarajat)'),
                    textSecondary,
                  ),
                  _buildChartLegend(
                    cSales,
                    _t('finance.weekly.sales', 'Sotuv summasi'),
                    textSecondary,
                  ),
                  _buildChartLegend(
                    cProfit,
                    _t('finance.weekly.profit', 'Jami foyda'),
                    textSecondary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 380,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                minY: 0,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => isDark
                        ? SmartStoreColors.darkSurfaceVariant
                        : const Color(0xFF0F172A),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    tooltipRoundedRadius: 10,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final p = _weekDayPoints[group.x.toInt()];
                      final String label;
                      final Color col;
                      final double rawY;
                      switch (rodIndex) {
                        case 0:
                          label = _t(
                            'finance.weekly.incoming',
                            'Kirim (ombor)',
                          );
                          col = cIncoming;
                          rawY = p.incoming.toDouble();
                          break;
                        case 1:
                          label = _t(
                            'finance.weekly.out_cost',
                            'Chiqim (xarajat)',
                          );
                          col = cOutCost;
                          rawY = p.outgoingCost.toDouble();
                          break;
                        case 2:
                          label = _t('finance.weekly.sales', 'Sotuv summasi');
                          col = cSales;
                          rawY = p.sales.toDouble();
                          break;
                        case 3:
                          label = _t('finance.weekly.profit', 'Jami foyda');
                          col = p.profit >= 0
                              ? cProfit
                              : const Color(0xFFEF4444);
                          rawY = p.profit.toDouble();
                          break;
                        default:
                          label = '';
                          col = textSecondary;
                          rawY = 0;
                      }
                      return BarTooltipItem(
                        '$label\n',
                        TextStyle(
                          fontSize: 10,
                          color: textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          TextSpan(
                            text: _formatMoney(rawY),
                            style: TextStyle(
                              fontSize: 12,
                              color: col,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      interval: max(step, 1),
                      getTitlesWidget: (value, meta) {
                        if (value < 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            _formatShort(value),
                            style: titlesStyle,
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= _weekDayPoints.length) {
                          return const SizedBox.shrink();
                        }
                        final p = _weekDayPoints[i];
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                weekdayFull[p.day.weekday - 1],
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${p.day.day.toString().padLeft(2, '0')}.${p.day.month.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color:
                        (isDark
                                ? SmartStoreColors.darkDivider
                                : const Color(0xFFE5E7EB))
                            .withValues(alpha: 0.5),
                    strokeWidth: 0.8,
                  ),
                ),
                borderData: FlBorderData(show: false),
                alignment: BarChartAlignment.spaceAround,
                groupsSpace: 18,
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: textMuted.withValues(alpha: 0.3),
                      strokeWidth: 1,
                    ),
                  ],
                ),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitCard({
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required bool isDark,
  }) {
    final totalCost = _outgoing.totalOriginalCost;
    final totalProfit = _outgoing.totalProfit;
    final isProfit = totalProfit >= 0;
    final profitColor = isProfit
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);
    final total = _outgoing.totalSalesAmount;
    final profitPct = total > 0 ? (totalProfit / total) * 100 : 0;
    final costPct = total > 0 ? (totalCost / total) * 100 : 0;
    final absProfit = totalProfit.abs().toDouble();
    final costDouble = totalCost.toDouble();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('finance.profit_title', 'Foyda'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF064E3B).withValues(alpha: 0.35)
                        : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF065F46)
                          : const Color(0xFFA7F3D0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(
                          'finance.profit_def',
                          'Foyda (Sotish narxi - Asl narx)',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatMoney(totalProfit),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: profitColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 140,
                height: 140,
                child: total > 0
                    ? PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 28,
                          sections: [
                            PieChartSectionData(
                              value: absProfit,
                              color: profitColor,
                              radius: 34,
                              showTitle: false,
                            ),
                            PieChartSectionData(
                              value: costDouble,
                              color: const Color(0xFF64748B),
                              radius: 34,
                              showTitle: false,
                            ),
                          ],
                        ),
                      )
                    : Center(
                        child: Text(
                          '-',
                          style: TextStyle(
                            fontSize: 24,
                            color: textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLegend(
                    color: profitColor,
                    label: _t(
                      'finance.legend_profit',
                      isProfit ? 'Foyda' : 'Zarar',
                    ),
                    pct: profitPct.abs(),
                    amount: totalProfit,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                  ),
                  const SizedBox(height: 14),
                  _buildLegend(
                    color: const Color(0xFF64748B),
                    label: _t('finance.legend_cost', 'Xarajat (asl narx)'),
                    pct: costPct,
                    amount: totalCost,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend({
    required Color color,
    required String label,
    required num pct,
    required num amount,
    required Color textPrimary,
    required Color textMuted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _formatMoney(amount),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildTopProductTables(
    Color cardBg,
    Color borderColor,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
    bool isDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildTopProductsCard(
            cardBg: cardBg,
            borderColor: borderColor,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: textMuted,
            isDark: isDark,
            title: _t('finance.top_incoming', 'Omborga kirgan mahsulotlar'),
            icon: Icons.inventory_rounded,
            iconColor: const Color(0xFF2563EB),
            isIncoming: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildTopProductsCard(
            cardBg: cardBg,
            borderColor: borderColor,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: textMuted,
            isDark: isDark,
            title: _t('finance.top_outgoing', 'Ombordan chiqqan mahsulotlar'),
            icon: Icons.remove_shopping_cart_rounded,
            iconColor: const Color(0xFFEF4444),
            isIncoming: false,
          ),
        ),
      ],
    );
  }

  Widget _buildTopProductsCard({
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required bool isDark,
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool isIncoming,
  }) {
    final map = isIncoming ? _incoming.byProduct : _outgoing.byProduct;
    final list = map.values.toList();
    list.sort((a, b) {
      final quantityOrder = b.quantity.compareTo(a.quantity);
      if (quantityOrder != 0) return quantityOrder;
      return b.totalValue.abs().compareTo(a.totalValue.abs());
    });
    final top = list;

    int totalQty = 0;
    num totalValue = 0;
    if (isIncoming) {
      totalQty = _incoming.totalQuantity;
      totalValue = _incoming.totalSellingValue ?? 0;
    } else {
      totalQty = _outgoing.totalQuantitySold;
      totalValue = _outgoing.totalSalesAmount;
    }

    final headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: textMuted,
      letterSpacing: 0.4,
    );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _t('finance.no_data', 'Ma\'lumot yo\'q'),
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? SmartStoreColors.darkBackground
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        _t('finance.col.product', 'Mahsulot nomi'),
                        style: headerStyle,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _t('finance.col.quantity', 'Miqdor'),
                        style: headerStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        isIncoming
                            ? _t('finance.col.total_value', 'Jami summa')
                            : _t(
                                'finance.col.selling_price',
                                'Sotish narxi (summa)',
                              ),
                        style: headerStyle,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),
            SizedBox(
              height: 300,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: top.length,
                itemBuilder: (context, index) {
                  final item = top[index];
                  final isLast = index == top.length - 1;
                  final qtyStr =
                      '${item.quantity} ${_t('common.pieces_small', 'dona')}';
                  final valStr = isIncoming
                      ? _formatMoney(item.totalValue)
                      : _formatMoney(item.totalValue);
                  final valColor = isIncoming
                      ? (item.totalValue < 0
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF2563EB))
                      : (item.totalValue < 0
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF10B981));
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Text(
                                item.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                qtyStr,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                valStr,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: valColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Divider(
                            height: 1,
                            color: borderColor.withValues(alpha: 0.4),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? SmartStoreColors.darkSurfaceVariant
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        _t('finance.total_label', 'Jami'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: textMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _formatQuantity(totalQty),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _formatMoney(totalValue),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isIncoming
                              ? const Color(0xFF2563EB)
                              : (_outgoing.totalProfit >= 0
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionLogTable(
    Color cardBg,
    Color borderColor,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
    bool isDark,
  ) {
    final headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: textMuted,
      letterSpacing: 0.3,
    );

    const rowHeight = 62.0;
    const headerHeight = 52.0;
    const visibleRowCount = 8;
    const tableMaxHeight = headerHeight + (visibleRowCount * rowHeight);

    final entries = _actionLogs;
    final sortedEntries = List<_ActionLogEntry>.from(entries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t('finance.recent_actions', 'So\'nggi harakatlar (Action log)'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            constraints: BoxConstraints(maxHeight: tableMaxHeight),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: headerHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? SmartStoreColors.darkSurfaceVariant
                        : const Color(0xFFF1F5F9),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Icon(
                          Icons.history_rounded,
                          size: 16,
                          color: textMuted,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _t('finance.log.date', 'Sana'),
                          style: headerStyle,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _t('finance.log.time', 'Vaqt'),
                          style: headerStyle,
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          _t('finance.log.second', 'Sek'),
                          style: headerStyle,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _t('finance.log.type', 'Amal turi'),
                          style: headerStyle,
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          _t('finance.log.product', 'Mahsulot'),
                          style: headerStyle,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _t('finance.log.quantity', 'Miqdor'),
                          style: headerStyle,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          _t('finance.log.amount', 'Summa'),
                          style: headerStyle,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _t('finance.log.user', 'Foydalanuvchi'),
                          style: headerStyle,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
                if (sortedEntries.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        _t('finance.no_actions', 'Harakatlar mavjud emas'),
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Scrollbar(
                      controller: _actionLogScrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _actionLogScrollController,
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: sortedEntries.length,
                        itemBuilder: (context, index) {
                          final entry = sortedEntries[index];
                          final isIncoming = entry.actionType == 'incoming';
                          final actionLabel = isIncoming
                              ? _t('finance.log.type_in', 'Kirim')
                              : _t('finance.log.type_out', 'Chiqim (sotish)');
                          final actionColor = isIncoming
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFEF4444);
                          final actionIcon = isIncoming
                              ? Icons.arrow_circle_down_rounded
                              : Icons.arrow_circle_up_rounded;
                          final amount = isIncoming
                              ? entry.originalPrice * entry.quantity
                              : entry.sellingPrice * entry.quantity;

                          return Container(
                            height: rowHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: borderColor.withValues(alpha: 0.4),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 36,
                                  child: Icon(
                                    actionIcon,
                                    size: 18,
                                    color: actionColor,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _formatDate(entry.timestamp),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    entry.timestamp.second.toString().padLeft(
                                      2,
                                      '0',
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textMuted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    actionLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: actionColor,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    entry.productName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    _formatQuantity(entry.quantity),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _formatMoney(amount),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: actionColor,
                                        ),
                                      ),
                                      if (!isIncoming && entry.profit != 0)
                                        Text(
                                          '${_t('finance.log.profit', 'F:')} ${_formatMoney(entry.profit)}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: entry.profit >= 0
                                                ? const Color(0xFF059669)
                                                : const Color(0xFFEF4444),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    entry.user,
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '${_t('finance.log_total_prefix', 'Jami:')} ${sortedEntries.length} ${_t('finance.log_total_suffix', 'ta harakat')}',
              style: TextStyle(
                fontSize: 12,
                color: textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

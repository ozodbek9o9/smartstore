import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import 'theme_controller.dart';
import '../utils/tenant_firestore.dart';

class _Document {
  const _Document(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  factory _Document.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => _Document(snapshot.id, snapshot.data());

  String text(String key, [String fallback = '']) {
    final value = data[key];
    return value == null
        ? fallback
        : value.toString().trim().isEmpty
        ? fallback
        : value.toString().trim();
  }

  num number(String key, {num fallback = 0}) {
    if (!data.containsKey(key)) return fallback;
    final val = data[key];
    if (val is num) return val;
    if (val is String) return num.tryParse(val) ?? fallback;
    return fallback;
  }

  DateTime date(String key, {DateTime? fallback}) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ??
          fallback ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }
    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<Map<String, dynamic>> list(String key) {
    final value = data[key];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class _CategoryStats {
  String name;
  num revenue = 0;
  num profit = 0;
  num previousRevenue = 0;
  _CategoryStats(this.name);
}

class _DailyStats {
  num revenue = 0;
  num profit = 0;
  num incoming = 0;
  num salesCount = 0;
  int customerCount = 0;
  final Set<String> saleIds = {};
}

class _ProductStats {
  String name;
  int sold = 0;
  int stock = 0;
  num soldValue = 0;
  _ProductStats(this.name);
}

class _CustomerStats {
  final int totalCustomers;
  final int todayCustomers;
  final int customersWithDebt;
  final num totalDebt;
  _CustomerStats({
    required this.totalCustomers,
    required this.todayCustomers,
    required this.customersWithDebt,
    required this.totalDebt,
  });
}

class _RangeTotals {
  int incomingQty = 0;
  num incomingValue = 0;
  num incomingQtySigned = 0;
  int outgoingQty = 0;
  num outgoingCost = 0;
  num outgoingSales = 0;
  num outgoingProfit = 0;
  int uniqueCustomers = 0;
  int orderCount = 0;
  Map<int, _DailyStats> daily = {};
  Map<int, _DailyStats> hourly = {};
  Map<String, _ProductStats> productOutgoing = {};
  Map<String, _CategoryStats> categoryStats = {};
  Map<int, _DailyStats> weekdayAgg = {
    for (var i = 1; i <= 7; i++) i: _DailyStats(),
  };
}

enum _Period { day, week, month }

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  bool _loading = true;
  Object? _error;

  List<_Document> _sales = [];
  List<_Document> _products = [];
  List<_Document> _customers = [];
  List<_Document> _entries = [];

  final Map<String, List<_Document>> _customerDebts = {};
  final Map<String, List<_Document>> _customerPayments = {};

  final List<StreamSubscription> _subscriptions = [];
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _debtSubscriptions = {};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _paymentSubscriptions = {};

  _Period _period = _Period.week;

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    _listenToData();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _listenToData() {
    void listen(
      CollectionReference<Map<String, dynamic>> reference,
      void Function(List<_Document>) update,
    ) {
      _subscriptions.add(
        reference.snapshots().listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              update(snapshot.docs.map(_Document.fromSnapshot).toList());
              _loading = false;
            });
          },
          onError: (e) {
            if (mounted) setState(() => _error = e);
          },
        ),
      );
    }

    listen(TenantFirestore.sales, (v) => _sales = v);
    listen(TenantFirestore.products, (v) => _products = v);
    listen(TenantFirestore.inventoryEntries, (v) => _entries = v);

    _subscriptions.add(
      TenantFirestore.customers.snapshots().listen(
        (snapshot) {
          if (!mounted) return;
          final customers = snapshot.docs.map(_Document.fromSnapshot).toList();
          _syncCustomerLedgerStreams(customers);
          setState(() {
            _customers = customers;
            _loading = false;
          });
        },
        onError: (e) {
          if (mounted) setState(() => _error = e);
        },
      ),
    );
  }

  void _syncCustomerLedgerStreams(List<_Document> customers) {
    final activeIds = customers.map((c) => c.id).toSet();
    for (final id in [..._debtSubscriptions.keys]) {
      if (!activeIds.contains(id)) {
        _debtSubscriptions.remove(id)?.cancel();
        _paymentSubscriptions.remove(id)?.cancel();
        _customerDebts.remove(id);
        _customerPayments.remove(id);
      }
    }
    for (final c in customers) {
      if (_debtSubscriptions.containsKey(c.id)) continue;
      _debtSubscriptions[c.id] = TenantFirestore.customerDebts(c.id)
          .snapshots()
          .listen((snap) {
            if (mounted) {
              setState(() {
                _customerDebts[c.id] = snap.docs
                    .map(_Document.fromSnapshot)
                    .toList();
              });
            }
          });
      _paymentSubscriptions[c.id] = TenantFirestore.customerPayments(c.id)
          .snapshots()
          .listen((snap) {
            if (mounted) {
              setState(() {
                _customerPayments[c.id] = snap.docs
                    .map(_Document.fromSnapshot)
                    .toList();
              });
            }
          });
    }
  }

  @override
  void dispose() {
    for (var s in _subscriptions) {
      s.cancel();
    }
    for (var s in _debtSubscriptions.values) {
      s.cancel();
    }
    for (var s in _paymentSubscriptions.values) {
      s.cancel();
    }
    super.dispose();
  }

  String _formatCurrency(num value) {
    final format = NumberFormat("#,##0", "uz_UZ");
    final sign = value < 0 ? '-' : '';
    return "$sign${format.format(value.abs()).replaceAll(',', ' ')} so'm";
  }

  // ---- period helpers ----
  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _startOfWeek(DateTime d) {
    final day = _startOfDay(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  ({DateTime start, DateTime end}) _getPeriodRange(_Period p, {DateTime? now}) {
    final n = now ?? DateTime.now();
    switch (p) {
      case _Period.day:
        final s = _startOfDay(n);
        return (start: s, end: n);
      case _Period.week:
        return (start: _startOfWeek(n), end: n);
      case _Period.month:
        return (start: _startOfMonth(n), end: n);
    }
  }

  ({DateTime start, DateTime end}) _getPreviousPeriodRange(
    _Period p, {
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    switch (p) {
      case _Period.day:
        final prev = _startOfDay(n.subtract(const Duration(days: 1)));
        return (
          start: prev,
          end: prev.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
        );
      case _Period.week:
        final endPrev = _startOfWeek(
          n,
        ).subtract(const Duration(microseconds: 1));
        final startPrev = _startOfWeek(endPrev);
        return (start: startPrev, end: endPrev);
      case _Period.month:
        final startPrev = DateTime(n.year, n.month - 1, 1);
        final endPrev = DateTime(
          n.year,
          n.month,
          1,
        ).subtract(const Duration(microseconds: 1));
        return (start: startPrev, end: endPrev);
    }
  }

  // ---- parse helpers (copy of finance_page logic) ----
  static num _parseNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    final r = num.tryParse(v.toString());
    if (r == null || r.isNaN || r.isInfinite) return 0;
    return r;
  }

  static int _parseInt(dynamic v) {
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

  static DateTime _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      final r = DateTime.tryParse(v);
      if (r != null) return r;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ---- Aggregate inventory_entries for a given time range ----
  _RangeTotals _aggregateRange(
    DateTime rangeStart,
    DateTime rangeEnd, {
    bool includeDaily = true,
    bool includeProducts = true,
  }) {
    final totals = _RangeTotals();
    final totalDays = math.max(0, rangeEnd.difference(rangeStart).inDays);
    final Set<String> customerIds = {};
    final Set<String> saleIds = {};
    final Map<String, String> prodToCat = {};
    for (var p in _products) {
      final c = p.text('category', p.text('type'));
      if (c.isNotEmpty) prodToCat[p.id] = c;
      final name = p.text(
        'productName',
        p.text('name', p.text('fullName', 'Nomsiz')),
      );
      totals.productOutgoing
          .putIfAbsent(p.id, () => _ProductStats(name))
          .stock = _parseInt(
        p.data['quantity'],
      );
    }

    if (includeDaily) {
      for (int i = 0; i <= totalDays; i++) {
        totals.daily[i] = _DailyStats();
      }
      for (int i = 0; i < 24; i++) {
        totals.hourly[i] = _DailyStats();
      }
    }

    final rs = _startOfDay(rangeStart);
    final re = _startOfDay(rangeEnd).add(const Duration(days: 1));

    if (includeDaily) {
      for (final customer in _customers) {
        final createdAt = customer.date(
          'createdAt',
          fallback: customer.date('lastActivity'),
        );
        if (createdAt.isBefore(rs) || !createdAt.isBefore(re)) continue;
        final dayIndex = _startOfDay(createdAt).difference(rs).inDays;
        totals.daily[dayIndex]!.customerCount++;
      }
    }

    for (var entry in _entries) {
      final d = entry.data;
      final type = (d['type'] as String?) ?? '';
      final productId = (d['productId'] as String?) ?? entry.id;
      final productName = (d['productName'] as String?) ?? '';
      final quantity = _parseInt(d['quantity']);
      final ts = _parseDate(d['timestamp']);
      final saleId = d['saleId']?.toString() ?? '';
      final customerId = d['customerId']?.toString() ?? '';

      if (ts.isBefore(rs) || !ts.isBefore(re)) continue;

      int dayIdx = 0;
      if (includeDaily) {
        dayIdx = _startOfDay(ts).difference(rs).inDays;
        if (dayIdx < 0) dayIdx = 0;
        if (dayIdx > totalDays) dayIdx = totalDays;
      }
      final weekday = ts.weekday;

      if (type == 'incoming') {
        final totalValue = _parseNum(d['totalValue']);
        final safeQty = quantity;
        final safeValue = totalValue;
        totals.incomingQty += safeQty;
        totals.incomingValue += safeValue;
        if (includeDaily) {
          totals.daily[dayIdx]!.incoming += safeValue;
          totals.hourly[ts.hour]!.incoming += safeValue;
        }
      } else if (type == 'outgoing' || type == 'adjustment_outgoing') {
        final totalCost = _parseNum(d['totalCostValue']);
        final isSale = type == 'outgoing';
        final totalSale = isSale ? _parseNum(d['totalSaleValue']) : 0;
        final totalProfit = isSale ? _parseNum(d['totalProfit']) : 0;
        final safeQty = quantity;
        final safeCost = totalCost;
        final safeSale = totalSale;

        totals.outgoingQty += safeQty;
        totals.outgoingCost += safeCost;
        totals.outgoingSales += safeSale;
        totals.outgoingProfit += totalProfit;
        if (isSale) {
          if (saleId.isNotEmpty) saleIds.add(saleId);
          if (customerId.isNotEmpty) customerIds.add(customerId);
        }

        if (includeDaily) {
          totals.daily[dayIdx]!.revenue += safeSale;
          totals.daily[dayIdx]!.profit += totalProfit;
          if (isSale) _addSaleCount(totals.daily[dayIdx]!, saleId, entry.id);
          totals.hourly[ts.hour]!.revenue += safeSale;
          totals.hourly[ts.hour]!.profit += totalProfit;
          if (isSale) _addSaleCount(totals.hourly[ts.hour]!, saleId, entry.id);
        }
        totals.weekdayAgg[weekday]!.revenue += safeSale;
        totals.weekdayAgg[weekday]!.profit += totalProfit;
        if (isSale) {
          _addSaleCount(totals.weekdayAgg[weekday]!, saleId, entry.id);
        }

        if (includeProducts && isSale) {
          final ps = totals.productOutgoing.putIfAbsent(
            productId,
            () => _ProductStats(productName),
          );
          ps.sold += safeQty;
          ps.soldValue += safeSale;
          final cat = prodToCat[productId] ?? 'Nomsiz';
          final cs = totals.categoryStats.putIfAbsent(
            cat,
            () => _CategoryStats(cat),
          );
          cs.revenue += safeSale;
          cs.profit += totalProfit;
        }
      }
    }
    for (final sale in _sales) {
      final ts = sale.date('timestamp');
      if (!ts.isBefore(rs) && ts.isBefore(re)) saleIds.add(sale.id);
    }
    totals.uniqueCustomers = customerIds.length;
    totals.orderCount = saleIds.length;
    return totals;
  }

  void _addSaleCount(_DailyStats stats, String saleId, String entryId) {
    final key = saleId.isNotEmpty ? saleId : entryId;
    if (stats.saleIds.add(key)) stats.salesCount += 1;
  }

  // ---- Customer stats (from customers + debts/payments) ----
  _CustomerStats _getCustomerStats() {
    final today = _startOfDay(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    int todayCustomers = 0;
    int customersWithDebt = 0;
    num remainingDebt = 0;

    // detect today's unique customers from sales + inventoryEntries outgoing
    final todayCustIds = <String>{};
    for (var s in _sales) {
      final ts = s.date('timestamp');
      if (!ts.isBefore(today) && ts.isBefore(tomorrow)) {
        final cid = s.text('customerId', s.text('customerName'));
        if (cid.isNotEmpty) todayCustIds.add(cid);
      }
    }
    for (var e in _entries) {
      final type = e.data['type']?.toString() ?? '';
      if (type != 'outgoing') continue;
      final ts = e.date('timestamp');
      if (!ts.isBefore(today) && ts.isBefore(tomorrow)) {
        final cid = e.text('customerId', '');
        if (cid.isNotEmpty) todayCustIds.add(cid);
      }
    }
    todayCustomers = todayCustIds.length;

    for (var c in _customers) {
      final rawDebt = c.number(
        'debt',
        fallback: c.number(
          'totalDebt',
          fallback: c.number(
            'balance',
            fallback: c.number('remainingDebt', fallback: 0),
          ),
        ),
      );
      num debts = 0;
      num payments = 0;
      for (var d in _customerDebts[c.id] ?? const []) {
        debts += d.number(
          'amount',
          fallback: d.number('total', fallback: d.number('value', fallback: 0)),
        );
      }
      for (var p in _customerPayments[c.id] ?? const []) {
        payments += p.number(
          'amount',
          fallback: p.number('total', fallback: p.number('value', fallback: 0)),
        );
      }
      final hasLedger =
          (_customerDebts[c.id]?.isNotEmpty ?? false) ||
          (_customerPayments[c.id]?.isNotEmpty ?? false);
      final ledgerRemaining = debts - payments;
      final total = hasLedger ? ledgerRemaining : rawDebt;
      if (total > 0) {
        customersWithDebt++;
        remainingDebt += total;
      } else if (total < 0 && rawDebt > 0) {
        customersWithDebt++;
        remainingDebt += rawDebt;
      }
    }

    return _CustomerStats(
      totalCustomers: _customers.length,
      todayCustomers: todayCustomers,
      customersWithDebt: customersWithDebt,
      totalDebt: remainingDebt,
    );
  }

  // ---- Sparkline data: last 7 days real daily ----
  List<FlSpot> _sparklineFor(num Function(_DailyStats) pick, num fallbackSeed) {
    final today = _startOfDay(DateTime.now());
    final start = today.subtract(const Duration(days: 6));
    final end = today;
    final agg = _aggregateRange(start, end);

    final rawValues = List<num>.filled(7, 0);
    for (int i = 0; i < 7; i++) {
      rawValues[i] = agg.daily[i] != null ? pick(agg.daily[i]!) : 0;
    }

    // detect true absence of data: ALL values are exactly 0
    final hasAnyRealData = rawValues.any((v) => v != 0);

    // scale: pick max magnitude to keep shape visible even for small numbers
    num maxMag = 0;
    for (final v in rawValues) {
      final a = v.abs();
      if (a > maxMag) maxMag = a;
    }
    final scale = maxMag > 0 ? (10 / maxMag) : 1.0;

    List<FlSpot> spots = [];
    for (int i = 0; i < 7; i++) {
      final val = rawValues[i];
      final y = hasAnyRealData ? (val * scale).toDouble() : 0.0;
      spots.add(FlSpot(i.toDouble(), y.isFinite && !y.isNaN ? y : 0));
    }

    if (!hasAnyRealData) {
      return List.generate(7, (i) => FlSpot(i.toDouble(), 0));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDarkMode;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final mutedColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Error: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(
                    isDark,
                    cardColor,
                    textColor,
                    mutedColor,
                    borderColor,
                  ),
                  const SizedBox(height: 24),
                  _buildHeaderMetrics(
                    cardColor,
                    textColor,
                    mutedColor,
                    borderColor,
                  ),
                  const SizedBox(height: 24),
                  _buildSalesDynamics(
                    cardColor,
                    textColor,
                    mutedColor,
                    borderColor,
                  ),
                  const SizedBox(height: 24),
                  _buildHighLowDays(
                    cardColor,
                    textColor,
                    mutedColor,
                    borderColor,
                  ),
                  const SizedBox(height: 24),
                  _buildCategoryPerformance(
                    cardColor,
                    textColor,
                    mutedColor,
                    borderColor,
                  ),
                  const SizedBox(height: 24),
                  _buildRecommendations(
                    cardColor,
                    textColor,
                    mutedColor,
                    borderColor,
                  ),
                  const SizedBox(height: 24),
                  _buildProfitExpenseAnalysis(
                    cardColor,
                    textColor,
                    mutedColor,
                    borderColor,
                  ),
                  const SizedBox(height: 24),
                  _buildUpcomingAlertsWidget(
                    cardColor,
                    textColor,
                    mutedColor,
                    borderColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    bool isDark,
    Color cardColor,
    Color textColor,
    Color mutedColor,
    Color borderColor,
  ) {
    final r = _getPeriodRange(_period);
    final pr = _getPreviousPeriodRange(_period);
    final dateFmt = DateFormat('dd MMMM yyyy');
    final curStr = _period == _Period.day
        ? dateFmt.format(r.start)
        : '${dateFmt.format(r.start)} - ${dateFmt.format(r.end)}';
    final prevStr = _period == _Period.day
        ? dateFmt.format(pr.start)
        : '${dateFmt.format(pr.start)} - ${dateFmt.format(pr.end)}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDropdown(
                  Icons.calendar_today,
                  curStr,
                  cardColor,
                  textColor,
                  borderColor,
                ),
                const SizedBox(width: 16),
                _buildDropdown(
                  null,
                  'Oldingi: $prevStr',
                  cardColor,
                  textColor,
                  borderColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    IconData? icon,
    String text,
    Color cardColor,
    Color textColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.keyboard_arrow_down, size: 16, color: textColor),
        ],
      ),
    );
  }

  Widget _buildHeaderMetrics(
    Color cardColor,
    Color textColor,
    Color mutedColor,
    Color borderColor,
  ) {
    final r = _getPeriodRange(_period);
    final pr = _getPreviousPeriodRange(_period);
    final cur = _aggregateRange(
      r.start,
      r.end,
      includeDaily: false,
      includeProducts: false,
    );
    final prev = _aggregateRange(
      pr.start,
      pr.end,
      includeDaily: false,
      includeProducts: false,
    );
    final cust = _getCustomerStats();

    final curSales = cur.outgoingSales;
    final prevSales = prev.outgoingSales;
    final salesPct = _calcPercentage(curSales, prevSales);

    final curProf = cur.outgoingProfit;
    final prevProf = prev.outgoingProfit;
    final profPct = _calcPercentage(curProf, prevProf);

    final curIncomingQty = cur.incomingQty;
    final prevIncomingQty = prev.incomingQty;
    final incomingPct = _calcPercentage(curIncomingQty, prevIncomingQty);

    final curCust = cust.totalCustomers;
    final prevCustCount = _customers.where((c) {
      final created = c.date('createdAt', fallback: c.date('lastActivity'));
      return created.isBefore(pr.end);
    }).length;
    final custPct = prevCustCount == 0
        ? (curCust == 0 ? 0.0 : 100.0)
        : _calcPercentage(curCust, prevCustCount).toDouble();

    final salesPctD = salesPct.toDouble();
    final profPctD = profPct.toDouble();
    final incomingPctD = incomingPct.toDouble();
    final custPctD = custPct.toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 650) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'Jami sotuv',
                      _formatCurrency(curSales),
                      salesPctD,
                      Colors.blue,
                      Icons.shopping_cart,
                      cardColor,
                      textColor,
                      mutedColor,
                      borderColor,
                      _sparklineFor((d) => d.revenue, salesPct),
                      sub: 'Buyurtmalar: ${cur.orderCount}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      'Jami foyda',
                      _formatCurrency(curProf),
                      profPctD,
                      Colors.green,
                      Icons.attach_money,
                      cardColor,
                      textColor,
                      mutedColor,
                      borderColor,
                      _sparklineFor((d) => d.profit, profPct),
                      sub: 'Foyda & Xarajat',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'analytics.incoming'.tr(),
                      '$curIncomingQty ta',
                      incomingPctD,
                      Colors.purple,
                      Icons.inventory_2,
                      cardColor,
                      textColor,
                      mutedColor,
                      borderColor,
                      _sparklineFor((d) => d.incoming, incomingPct),
                      sub: _formatCurrency(cur.incomingValue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      'analytics.customers'.tr(),
                      '$curCust ta',
                      custPctD,
                      Colors.orange,
                      Icons.people,
                      cardColor,
                      textColor,
                      mutedColor,
                      borderColor,
                      _sparklineFor((d) => d.customerCount, custPct),
                      sub:
                          'Qarzdor: ${cust.customersWithDebt} (${_formatCurrency(cust.totalDebt)})',
                    ),
                  ),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Jami sotuv',
                _formatCurrency(curSales),
                salesPctD,
                Colors.blue,
                Icons.shopping_cart,
                cardColor,
                textColor,
                mutedColor,
                borderColor,
                _sparklineFor((d) => d.revenue, salesPct),
                sub: 'Buyurtmalar: ${cur.orderCount}',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                'Jami foyda',
                _formatCurrency(curProf),
                profPctD,
                Colors.green,
                Icons.attach_money,
                cardColor,
                textColor,
                mutedColor,
                borderColor,
                _sparklineFor((d) => d.profit, profPct),
                sub: 'Xarajat: ${_formatCurrency(cur.outgoingCost)}',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                'analytics.incoming'.tr(),
                '$curIncomingQty ta',
                incomingPctD,
                Colors.purple,
                Icons.inventory_2,
                cardColor,
                textColor,
                mutedColor,
                borderColor,
                _sparklineFor((d) => d.incoming, incomingPct),
                sub: _formatCurrency(cur.incomingValue),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                'analytics.customers'.tr(),
                '$curCust ta',
                custPctD,
                Colors.orange,
                Icons.people,
                cardColor,
                textColor,
                mutedColor,
                borderColor,
                _sparklineFor((d) => d.customerCount, custPct),
                sub:
                    'Qarzdor ${cust.customersWithDebt}: ${_formatCurrency(cust.totalDebt)}',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    double pct,
    Color color,
    IconData icon,
    Color cardColor,
    Color textColor,
    Color mutedColor,
    Color borderColor,
    List<FlSpot> spark, {
    required String sub,
  }) {
    final isPos = pct >= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: mutedColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: TextStyle(color: mutedColor, fontSize: 11),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Icon(
                isPos ? Icons.arrow_upward : Icons.arrow_downward,
                color: isPos ? Colors.green : Colors.red,
                size: 12,
              ),
              Text(
                '${pct.abs().toStringAsFixed(1)}%',
                style: TextStyle(
                  color: isPos ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              Text(
                'analytics.vs_previous'.tr(),
                style: TextStyle(color: mutedColor, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spark,
                    isCurved: true,
                    color: color,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, bar) => spot.x == 6,
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calcPercentage(num current, num previous) {
    if (previous == 0) return current > 0 ? 100.0 : 0.0;
    return ((current - previous) / previous) * 100;
  }

  Widget _buildSalesDynamics(
    Color cardColor,
    Color textColor,
    Color mutedColor,
    Color borderColor,
  ) {
    DateTime now = DateTime.now();
    DateTime rStart;
    DateTime rEnd = now;
    DateTime prStart;
    DateTime prEnd;

    if (_period == _Period.day) {
      rStart = _startOfDay(now);
      prStart = rStart.subtract(const Duration(days: 1));
      prEnd = rStart.subtract(const Duration(microseconds: 1));
    } else if (_period == _Period.week) {
      rStart = _startOfWeek(now);
      prEnd = rStart.subtract(const Duration(microseconds: 1));
      prStart = _startOfWeek(prEnd);
    } else {
      rStart = _startOfDay(now).subtract(const Duration(days: 14));
      prEnd = rStart.subtract(const Duration(microseconds: 1));
      prStart = _startOfDay(prEnd).subtract(const Duration(days: 14));
    }

    final cur = _aggregateRange(
      rStart,
      rEnd,
      includeDaily: true,
      includeProducts: false,
    );
    final prev = _aggregateRange(
      prStart,
      prEnd,
      includeDaily: true,
      includeProducts: false,
    );

    int chartLen;
    List<FlSpot> curSpots;
    List<FlSpot> prevSpots;
    List<num> curRaw = [];
    List<num> prevRaw = [];
    Widget Function(double, TitleMeta) bottomTitleFn;
    double interval = 1;
    DateTime chartStart = rStart;

    if (_period == _Period.day) {
      chartLen = 24;
      interval = 4;
      curSpots = List.filled(chartLen, const FlSpot(0, 0));
      prevSpots = List.filled(chartLen, const FlSpot(0, 0));
      curRaw = List.filled(chartLen, 0);
      prevRaw = List.filled(chartLen, 0);
      for (int i = 0; i < 24; i++) {
        final cVal = cur.hourly[i]?.revenue ?? 0;
        final pVal = prev.hourly[i]?.revenue ?? 0;
        curSpots[i] = FlSpot(i.toDouble(), cVal / 1000000);
        prevSpots[i] = FlSpot(i.toDouble(), pVal / 1000000);
        curRaw[i] = cVal;
        prevRaw[i] = pVal;
      }
      bottomTitleFn = (v, meta) {
        final slot = v.toInt();
        if (slot < 0 || slot >= chartLen || slot % 4 != 0) {
          return const SizedBox.shrink();
        }
        return SideTitleWidget(
          meta: meta,
          space: 4,
          child: Text(
            '$slot:00',
            style: TextStyle(color: mutedColor, fontSize: 9),
          ),
        );
      };
    } else if (_period == _Period.week) {
      chartLen = 7;
      interval = 1;
      curSpots = List.filled(chartLen, const FlSpot(0, 0));
      prevSpots = List.filled(chartLen, const FlSpot(0, 0));
      curRaw = List.filled(chartLen, 0);
      prevRaw = List.filled(chartLen, 0);
      int totalDays = math.max(0, rEnd.difference(rStart).inDays);
      int totalPrevDays = math.max(0, prEnd.difference(prStart).inDays);
      final curSliceStart = math.max(0, totalDays - chartLen + 1);
      final prevSliceStart = math.max(0, totalPrevDays - chartLen + 1);
      for (int slot = 0; slot < chartLen; slot++) {
        final curVal = cur.daily[curSliceStart + slot]?.revenue ?? 0;
        final prevVal = prev.daily[prevSliceStart + slot]?.revenue ?? 0;
        curSpots[slot] = FlSpot(slot.toDouble(), curVal / 1000000);
        prevSpots[slot] = FlSpot(slot.toDouble(), prevVal / 1000000);
        curRaw[slot] = curVal;
        prevRaw[slot] = prevVal;
      }
      chartStart = rStart;
      bottomTitleFn = (v, meta) {
        final slot = v.toInt();
        if (slot < 0 || slot >= chartLen) return const SizedBox.shrink();
        final d = _startOfDay(chartStart).add(Duration(days: slot));
        return SideTitleWidget(
          meta: meta,
          space: 4,
          child: Text(
            DateFormat('EEE').format(d),
            style: TextStyle(color: mutedColor, fontSize: 9),
          ),
        );
      };
    } else {
      chartLen = 15;
      interval = 3;
      curSpots = List.filled(chartLen, const FlSpot(0, 0));
      prevSpots = List.filled(chartLen, const FlSpot(0, 0));
      curRaw = List.filled(chartLen, 0);
      prevRaw = List.filled(chartLen, 0);
      int totalDays = math.max(0, rEnd.difference(rStart).inDays);
      int totalPrevDays = math.max(0, prEnd.difference(prStart).inDays);
      final curSliceStart = math.max(0, totalDays - chartLen + 1);
      final prevSliceStart = math.max(0, totalPrevDays - chartLen + 1);
      for (int slot = 0; slot < chartLen; slot++) {
        final curVal = cur.daily[curSliceStart + slot]?.revenue ?? 0;
        final prevVal = prev.daily[prevSliceStart + slot]?.revenue ?? 0;
        curSpots[slot] = FlSpot(slot.toDouble(), curVal / 1000000);
        prevSpots[slot] = FlSpot(slot.toDouble(), prevVal / 1000000);
        curRaw[slot] = curVal;
        prevRaw[slot] = prevVal;
      }
      chartStart = rStart;
      bottomTitleFn = (v, meta) {
        final slot = v.toInt();
        if (slot < 0 || slot >= chartLen || slot % 3 != 0) {
          return const SizedBox.shrink();
        }
        final d = _startOfDay(chartStart).add(Duration(days: slot));
        return SideTitleWidget(
          meta: meta,
          space: 4,
          child: Text(
            DateFormat('d MMM').format(d),
            style: TextStyle(color: mutedColor, fontSize: 9),
          ),
        );
      };
    }

    return _buildCardWrapper(
      title: 'analytics.sales_dynamics'.tr(),
      cardColor: cardColor,
      borderColor: borderColor,
      textColor: textColor,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPillButton(
            'Kun',
            _period == _Period.day,
            () => setState(() => _period = _Period.day),
          ),
          _buildPillButton(
            'analytics.week'.tr(),
            _period == _Period.week,
            () => setState(() => _period = _Period.week),
          ),
          _buildPillButton(
            'analytics.month'.tr(),
            _period == _Period.month,
            () => setState(() => _period = _Period.month),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildLegendItem(
                'analytics.current_period'.tr(),
                Colors.blue,
                textColor,
              ),
              const SizedBox(width: 16),
              _buildLegendItem(
                'analytics.previous_period'.tr(),
                Colors.grey.shade400,
                textColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 230,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                      final value = spot.y;
                      final formatted = value.abs() >= 1000000
                          ? '${(value / 1000000).toStringAsFixed(1)}M'
                          : value.abs() >= 1000
                          ? '${(value / 1000).toStringAsFixed(0)}K'
                          : value.toStringAsFixed(0);
                      return LineTooltipItem(
                        formatted,
                        TextStyle(
                          color: spot.barIndex == 0
                              ? Colors.blue
                              : Colors.grey.shade400,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }).toList(),
                  ),
                  handleBuiltInTouches: true,
                  touchCallback:
                      (FlTouchEvent event, LineTouchResponse? response) {
                        if (event is! FlTapUpEvent) return;
                        if (response == null ||
                            response.lineBarSpots == null ||
                            response.lineBarSpots!.isEmpty) {
                          return;
                        }
                        final x = response.lineBarSpots!.first.x.toInt();
                        if (x < 0 || x >= chartLen) return;
                        _showChartModal(
                          context,
                          x,
                          curRaw[x],
                          prevRaw[x],
                          _period,
                          chartStart,
                        );
                      },
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: borderColor,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      getTitlesWidget: (v, meta) {
                        if (v == 0) {
                          return SideTitleWidget(
                            meta: meta,
                            space: 6,
                            child: Text(
                              '0',
                              style: TextStyle(color: mutedColor, fontSize: 10),
                            ),
                          );
                        }
                        String text;
                        final absV = v.abs();
                        final sign = v < 0 ? '-' : '';
                        if (absV >= 1) {
                          text =
                              '$sign${absV.toStringAsFixed(absV.truncateToDouble() == absV ? 0 : 1)}M';
                        } else {
                          text = '$sign${(absV * 1000).toInt()}K';
                        }
                        return SideTitleWidget(
                          meta: meta,
                          space: 6,
                          child: Text(
                            text,
                            style: TextStyle(color: mutedColor, fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: interval,
                      reservedSize: 22,
                      getTitlesWidget: bottomTitleFn,
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: curSpots,
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 2.2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (s, p, bar, i) => FlDotCirclePainter(
                        radius: 2.6,
                        color: Colors.blue,
                        strokeWidth: 0,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blue.withValues(alpha: 0.08),
                    ),
                  ),
                  LineChartBarData(
                    spots: prevSpots,
                    isCurved: true,
                    color: Colors.grey.shade400,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChartModal(
    BuildContext context,
    int index,
    num currentVal,
    num prevVal,
    _Period period,
    DateTime startRange,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final mutedColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);

    String timeLabel = '';
    if (period == _Period.day) {
      timeLabel = 'Soat $index:00 - ${index + 1}:00';
    } else if (period == _Period.week) {
      final d = _startOfDay(startRange).add(Duration(days: index));
      timeLabel = DateFormat('dd MMMM, EEEE', 'uz_UZ').format(d);
    } else {
      final d = _startOfDay(startRange).add(Duration(days: index));
      timeLabel = DateFormat('dd MMMM yyyy').format(d);
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            width: 300, // Make it compact
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      timeLabel,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: mutedColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close, color: mutedColor, size: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildModalCard(
                  'analytics.current_period'.tr(),
                  currentVal,
                  Colors.blue,
                  textColor,
                  mutedColor,
                  isDark,
                ),
                const SizedBox(height: 12),
                _buildModalCard(
                  'analytics.previous_period'.tr(),
                  prevVal,
                  Colors.grey,
                  textColor,
                  mutedColor,
                  isDark,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModalCard(
    String title,
    num value,
    Color themeColor,
    Color textColor,
    Color mutedColor,
    bool isDark,
  ) {
    final isNegative = value < 0;
    final displayColor = isNegative ? Colors.red : textColor;
    final format = NumberFormat("#,##0", "en_US");
    final formatted = format.format(value.abs());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: themeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "${isNegative ? '-' : ''}$formatted so'm",
            style: TextStyle(
              color: displayColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighLowDays(
    Color cardColor,
    Color textColor,
    Color mutedColor,
    Color borderColor,
  ) {
    final r = _getPeriodRange(_period);
    final cur = _aggregateRange(
      r.start,
      r.end,
      includeDaily: false,
      includeProducts: false,
    );
    final weekdayStats = cur.weekdayAgg;
    final days = [
      'Dushanba',
      'Seshanba',
      'Chorshanba',
      'Payshanba',
      'Juma',
      'Shanba',
      'Yakshanba',
    ];
    int highDay = 1, lowDay = 1;
    num maxRev = -1, minRev = double.infinity;
    weekdayStats.forEach((d, s) {
      if (s.revenue > maxRev) {
        maxRev = s.revenue;
        highDay = d;
      }
      if (s.salesCount > 0 && s.revenue < minRev) {
        minRev = s.revenue;
        lowDay = d;
      }
    });
    if (minRev == double.infinity) {
      minRev = 0;
      lowDay = highDay;
    }
    if (maxRev < 0) maxRev = 0;
    final maxScale = math.max(maxRev.toDouble(), 1.0);

    final totalRevenue = weekdayStats.values.fold<num>(
      0,
      (a, b) => a + b.revenue,
    );
    final totalOrders = weekdayStats.values.fold<num>(
      0,
      (a, b) => a + b.salesCount,
    );
    final totalProfit = weekdayStats.values.fold<num>(
      0,
      (a, b) => a + b.profit,
    );

    void showHighLowModal() {
      final isDark = ThemeController.instance.isDarkMode;
      final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
      final modalTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
      final modalMutedColor = isDark
          ? Colors.grey.shade400
          : const Color(0xFF64748B);

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 48,
            ),
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
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
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.bar_chart_rounded,
                            color: Colors.blue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'analytics.highlow_modal_title'.tr(),
                            style: TextStyle(
                              color: modalTextColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(ctx).pop(),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: modalMutedColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              color: modalMutedColor,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _buildModalStatChip(
                          'analytics.highlow_total_revenue'.tr(),
                          _formatCurrency(totalRevenue),
                          Colors.blue,
                          isDark,
                          modalTextColor,
                          modalMutedColor,
                        ),
                        const SizedBox(width: 10),
                        _buildModalStatChip(
                          'analytics.highlow_total_orders'.tr(),
                          '${totalOrders.toInt()} ta',
                          Colors.green,
                          isDark,
                          modalTextColor,
                          modalMutedColor,
                        ),
                        const SizedBox(width: 10),
                        _buildModalStatChip(
                          'analytics.highlow_total_profit'.tr(),
                          _formatCurrency(totalProfit),
                          Colors.orange,
                          isDark,
                          modalTextColor,
                          modalMutedColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _buildHighLowChip(
                            label: 'analytics.highlow_best_day'.tr(),
                            day: days[highDay - 1],
                            amount: _formatCurrency(maxRev),
                            orders:
                                weekdayStats[highDay]?.salesCount.toInt() ?? 0,
                            color: Colors.green,
                            icon: Icons.arrow_upward,
                            isDark: isDark,
                            textColor: modalTextColor,
                            mutedColor: modalMutedColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildHighLowChip(
                            label: 'analytics.highlow_worst_day'.tr(),
                            day: days[lowDay - 1],
                            amount: _formatCurrency(minRev),
                            orders:
                                weekdayStats[lowDay]?.salesCount.toInt() ?? 0,
                            color: Colors.red,
                            icon: Icons.arrow_downward,
                            isDark: isDark,
                            textColor: modalTextColor,
                            mutedColor: modalMutedColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'analytics.highlow_by_day'.tr(),
                      style: TextStyle(
                        color: modalMutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(7, (i) {
                      final d = i + 1;
                      final s = weekdayStats[d]!;
                      final isHigh = d == highDay && maxRev > 0;
                      final isLow =
                          d == lowDay && minRev < maxRev && s.salesCount > 0;
                      final barFraction = maxScale > 0
                          ? (s.revenue / maxScale).clamp(0.0, 1.0)
                          : 0.0;
                      final rowColor = isHigh
                          ? Colors.green
                          : (isLow ? Colors.red : Colors.blue);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 76,
                              child: Text(
                                days[i],
                                style: TextStyle(
                                  color: (isHigh || isLow)
                                      ? rowColor
                                      : modalTextColor,
                                  fontSize: 12,
                                  fontWeight: (isHigh || isLow)
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Stack(
                                children: [
                                  Container(
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: barFraction,
                                    child: Container(
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: rowColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: Text(
                                _formatCurrency(s.revenue),
                                style: TextStyle(
                                  color: (isHigh || isLow)
                                      ? rowColor
                                      : modalTextColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${s.salesCount.toInt()}ta',
                                style: TextStyle(
                                  color: modalMutedColor,
                                  fontSize: 10,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(
                        'analytics.close'.tr(),
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return _buildCardWrapper(
      title: 'analytics.highlow_title'.tr(),
      cardColor: cardColor,
      borderColor: borderColor,
      textColor: textColor,
      action: GestureDetector(
        onTap: showHighLowModal,
        child: Tooltip(
          message: 'analytics.highlow_modal_title'.tr(),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.info_outline, color: Colors.blue, size: 18),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'analytics.highlow_best_label'.tr(),
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.arrow_upward,
                            color: Colors.green,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                days[highDay - 1],
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                _formatCurrency(maxRev),
                                style: TextStyle(
                                  color: mutedColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'analytics.highlow_worst_label'.tr(),
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.arrow_downward,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                days[lowDay - 1],
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                _formatCurrency(minRev),
                                style: TextStyle(
                                  color: mutedColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(7, (i) {
                    final d = i + 1;
                    final c = d == highDay
                        ? Colors.green
                        : (d == lowDay &&
                                  minRev < maxRev &&
                                  (weekdayStats[d]?.salesCount ?? 0) > 0
                              ? Colors.red
                              : Colors.blue);
                    return _buildDayBar(
                      days[i],
                      weekdayStats[d]?.revenue ?? 0,
                      maxScale,
                      c,
                      textColor,
                      mutedColor,
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModalStatChip(
    String label,
    String value,
    Color color,
    bool isDark,
    Color textColor,
    Color mutedColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: mutedColor, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighLowChip({
    required String label,
    required String day,
    required String amount,
    required int orders,
    required Color color,
    required IconData icon,
    required bool isDark,
    required Color textColor,
    required Color mutedColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: mutedColor, fontSize: 10)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  day,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '$orders ta buyurtma',
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildDayBar(
    String day,
    num revenue,
    double maxRevenue,
    Color color,
    Color textColor,
    Color mutedColor,
  ) {
    final value = revenue.toDouble();
    final max = maxRevenue;
    final String label;
    if (value >= 1000000) {
      label = '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      label = '${(value / 1000).toStringAsFixed(0)}K';
    } else if (value > 0) {
      label = value.toInt().toString();
    } else {
      label = '0';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(day, style: TextStyle(color: mutedColor, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: max > 0 ? (value / max).clamp(0.0, 1.0) : 0,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: TextStyle(
                color: color == Colors.red
                    ? Colors.red
                    : (color == Colors.green ? Colors.green : textColor),
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPerformance(
    Color cardColor,
    Color textColor,
    Color mutedColor,
    Color borderColor,
  ) {
    final r = _getPeriodRange(_period);
    final pr = _getPreviousPeriodRange(_period);
    final cur = _aggregateRange(
      r.start,
      r.end,
      includeDaily: false,
      includeProducts: true,
    );
    final prev = _aggregateRange(
      pr.start,
      pr.end,
      includeDaily: false,
      includeProducts: true,
    );

    final catStats = <String, _CategoryStats>{};
    for (final e in cur.categoryStats.entries) {
      catStats[e.key] = e.value;
    }
    for (final e in prev.categoryStats.entries) {
      catStats.putIfAbsent(e.key, () => _CategoryStats(e.key)).previousRevenue =
          e.value.revenue;
    }

    const icons = [
      Icons.local_drink,
      Icons.fastfood,
      Icons.home,
      Icons.set_meal,
      Icons.apple,
    ];
    const colors = [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.red,
      Colors.purple,
    ];
    final sorted = catStats.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    final top = sorted.take(5).toList();

    return _buildCardWrapper(
      title: 'analytics.category_performance'.tr(),
      cardColor: cardColor,
      borderColor: borderColor,
      textColor: textColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 550;
              return Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Kategoriya',
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!isCompact)
                    Expanded(
                      child: Text(
                        'analytics.sale'.tr(),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (!isCompact)
                    Expanded(
                      child: Text(
                        'analytics.profit'.tr(),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      'O\'sish',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const Divider(height: 24),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'analytics.no_data'.tr(),
                style: TextStyle(color: mutedColor),
              ),
            ),
          ...top.asMap().entries.map((e) {
            final idx = e.key;
            final stat = e.value;
            final growth = _calcPercentage(stat.revenue, stat.previousRevenue);
            return _buildCategoryRow(
              stat.name,
              _formatCurrency(stat.revenue),
              _formatCurrency(stat.profit),
              growth,
              icons[idx % icons.length],
              colors[idx % colors.length],
              textColor,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(
    String name,
    String sales,
    String profit,
    double growth,
    IconData icon,
    Color color,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 550;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isCompact) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sales,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    profit,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      growth >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      color: growth >= 0 ? Colors.green : Colors.red,
                      size: 12,
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        '${growth.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: growth >= 0 ? Colors.green : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRecommendations(
    Color cardColor,
    Color textColor,
    Color mutedColor,
    Color borderColor,
  ) {
    final now = DateTime.now();
    final r = (start: _startOfMonth(now), end: now);
    final cur = _aggregateRange(
      r.start,
      r.end,
      includeDaily: false,
      includeProducts: true,
    );

    for (final product in _products) {
      final stats = cur.productOutgoing.putIfAbsent(
        product.id,
        () => _ProductStats(
          product.text('productName', product.text('name', 'Nomsiz')),
        ),
      );
      stats.stock = math.max(0, product.number('quantity').toInt());
    }

    final pList = cur.productOutgoing.values.toList();
    final needMore =
        pList.where((p) => p.sold >= 2 && p.stock < p.sold / 2).toList()
          ..sort((a, b) => b.sold.compareTo(a.sold));
    final needLess =
        pList
            .where((p) => p.stock > 0 && (p.sold == 0 || p.stock >= p.sold * 3))
            .toList()
          ..sort((a, b) => a.sold.compareTo(b.sold));

    return _buildCardWrapper(
      title: 'Olingan mahsulotlar tavsiyasi (Keyingi oy)',
      cardColor: cardColor,
      borderColor: borderColor,
      textColor: textColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 600;
          if (isCompact) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRecColumn(true, needMore, mutedColor, textColor),
                const SizedBox(height: 24),
                _buildRecColumn(false, needLess, mutedColor, textColor),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildRecColumn(true, needMore, mutedColor, textColor),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildRecColumn(false, needLess, mutedColor, textColor),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRecColumn(
    bool isNeedMore,
    List<_ProductStats> list,
    Color mutedColor,
    Color textColor,
  ) {
    final color = isNeedMore ? Colors.green : Colors.red;
    final icon = isNeedMore ? Icons.check_circle : Icons.cancel;
    final title = isNeedMore
        ? 'Ko\'proq olish kerak'
        : 'analytics.less_purchase'.tr();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildRecTableHead(mutedColor),
        const Divider(height: 16),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Tavsiyalar yo\'q',
              style: TextStyle(color: mutedColor),
              textAlign: TextAlign.center,
            ),
          ),
        ...list
            .take(5)
            .map(
              (p) => _buildRecRow(
                p.name,
                p.sold,
                isNeedMore
                    ? math.max(1, p.sold - p.stock)
                    : -math.max(1, p.stock - p.sold),
                textColor,
                isNeedMore,
              ),
            ),
      ],
    );
  }

  Widget _buildRecTableHead(Color mutedColor) => Row(
    children: [
      Expanded(
        flex: 3,
        child: Text(
          'Mahsulot',
          style: TextStyle(color: mutedColor, fontSize: 11),
        ),
      ),
      Expanded(
        child: Text(
          'Talab',
          textAlign: TextAlign.right,
          style: TextStyle(color: mutedColor, fontSize: 11),
        ),
      ),
      Expanded(
        child: Text(
          'analytics.recommendation'.tr(),
          textAlign: TextAlign.right,
          style: TextStyle(color: mutedColor, fontSize: 11),
        ),
      ),
    ],
  );

  Widget _buildRecRow(
    String name,
    int prog,
    int tavs,
    Color textColor,
    bool isPos,
  ) {
    final color = isPos ? Colors.green : Colors.red;
    final icon = isPos ? Icons.arrow_upward : Icons.arrow_downward;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(icon, color: color, size: 10),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    '${prog.abs()} dona',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${tavs > 0 ? '+' : ''}$tavs dona',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitExpenseAnalysis(
    Color cardColor,
    Color textColor,
    Color mutedColor,
    Color borderColor,
  ) {
    final today = _startOfDay(DateTime.now());
    final chartStart = _startOfWeek(today);
    final chartEnd = chartStart.add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    );
    final cur = _aggregateRange(
      chartStart,
      chartEnd,
      includeDaily: true,
      includeProducts: false,
    );
    int totalDays = chartEnd.difference(chartStart).inDays;
    int maxBars = _period == _Period.month ? 14 : 7;
    int startDay = math.max(0, totalDays - maxBars + 1);

    List<BarChartGroupData> barGroups = [];
    for (int i = startDay; i <= totalDays; i++) {
      final rev = cur.daily[i]?.revenue ?? 0;
      final prof = cur.daily[i]?.profit ?? 0;
      num exp = rev - prof;
      if (exp < 0) exp = 0;
      barGroups.add(
        _buildBarGroup(i - startDay, prof.toDouble(), exp.toDouble()),
      );
    }
    if (barGroups.isEmpty) barGroups.add(_buildBarGroup(0, 0, 0));

    return _buildCardWrapper(
      title: 'analytics.profit_cost_analysis'.tr(),
      cardColor: cardColor,
      borderColor: borderColor,
      textColor: textColor,
      action: Row(
        children: [
          _buildLegendItem('analytics.profit'.tr(), Colors.green, textColor),
          const SizedBox(width: 16),
          _buildLegendItem('analytics.cost'.tr(), Colors.red, textColor),
        ],
      ),
      child: SizedBox(
        height: 260,
        child: BarChart(
          BarChartData(
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF334155),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final label = rodIndex == 0
                      ? 'analytics.profit'.tr()
                      : 'analytics.cost'.tr();
                  return BarTooltipItem(
                    '$label\n${_formatCurrency(rod.toY)}',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (v) =>
                  FlLine(color: borderColor, strokeWidth: 1, dashArray: [4, 4]),
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 76,
                  getTitlesWidget: (v, meta) {
                    return SideTitleWidget(
                      meta: meta,
                      space: 8,
                      child: Text(
                        _formatCurrency(v).replaceAll(" so'm", ''),
                        style: TextStyle(color: mutedColor, fontSize: 11),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  getTitlesWidget: (v, meta) {
                    final d = chartStart.add(
                      Duration(days: startDay + v.toInt()),
                    );
                    final label = _startOfDay(d) == today
                        ? 'analytics.today'.tr()
                        : DateFormat('EEE').format(d);
                    return SideTitleWidget(
                      meta: meta,
                      space: 8,
                      child: Text(
                        label,
                        style: TextStyle(color: mutedColor, fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: barGroups,
          ),
        ),
      ),
    );
  }

  BarChartGroupData _buildBarGroup(int x, double y1, double y2) =>
      BarChartGroupData(
        x: x,
        barRods: [
          BarChartRodData(
            toY: y1,
            color: Colors.green,
            width: 12,
            borderRadius: BorderRadius.circular(2),
          ),
          BarChartRodData(
            toY: y2,
            color: Colors.red,
            width: 12,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      );

  Widget _buildUpcomingAlertsWidget(
    Color cardColor,
    Color textColor,
    Color mutedColor,
    Color borderColor,
  ) {
    List<String> alerts = [];
    int outOfStock = 0;
    for (var p in _products) {
      if (p.number('quantity') <= 5) outOfStock++;
    }
    if (outOfStock > 0) {
      alerts.add('$outOfStock ta mahsulot zaxirasi kam (5 dan oz)');
    }
    final cust = _getCustomerStats();
    if (cust.customersWithDebt > 0) {
      alerts.add(
        'Qarzdor mijozlar: ${cust.customersWithDebt} ta (${_formatCurrency(cust.totalDebt)})',
      );
    }
    if (alerts.isEmpty) alerts.add('analytics.no_warnings'.tr());

    return _buildCardWrapper(
      title: 'analytics.upcoming_warnings'.tr(),
      cardColor: cardColor,
      borderColor: borderColor,
      textColor: textColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var alert in alerts)
            _buildAlertItem(
              Icons.warning_amber_rounded,
              Colors.orange,
              alert,
              textColor,
            ),
          if (alerts.length < 4)
            _buildAlertItem(
              Icons.check_circle_outline,
              Colors.green,
              'analytics.new_orders_expected'.tr(),
              textColor,
            ),
        ],
      ),
    );
  }

  Widget _buildAlertItem(
    IconData icon,
    Color color,
    String text,
    Color textColor,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildCardWrapper({
    required String title,
    required Widget child,
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (action != null) ...[const SizedBox(width: 12), action],
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildPillButton(String text, bool isSelected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey.shade300,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.blue : Colors.grey.shade600,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      );

  Widget _buildLegendItem(String text, Color color, Color textColor) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 4,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/sales_report_calculator.dart';
import 'theme_controller.dart';
import '../utils/tenant_firestore.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  static const _periods = ReportPeriod.values;
  static const _turnoverPrevious = Color(0xFF1688E8);
  static const _turnoverCurrent = Color(0xFF79BDF5);
  static const _profitPrevious = Color(0xFF8B5CF6);
  static const _profitCurrent = Color(0xFFEF75B5);

  final _scrollController = ScrollController();
  final _sectionKeys = {for (final period in _periods) period: GlobalKey()};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _salesSubscription;
  List<SalesReportRecord> _sales = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    _listenToSales();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    _salesSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _listenToSales() {
    _salesSubscription = TenantFirestore.sales.snapshots().listen(
      (snapshot) {
        final sales = snapshot.docs
            .map((doc) => SalesReportRecord.fromMap(doc.data()))
            .whereType<SalesReportRecord>()
            .toList(growable: false);
        if (!mounted) return;
        setState(() {
          _sales = sales;
          _loading = false;
          _error = null;
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = error;
        });
      },
    );
  }

  String _tr(String key, String fallback) {
    final value = key.tr();
    return value == key || value.isEmpty ? fallback : value;
  }

  String _formatMoney(num value) {
    final formatted = NumberFormat(
      '#,##0',
      'uz_UZ',
    ).format(value.abs()).replaceAll(',', ' ');
    return '${value < 0 ? '-' : ''}$formatted so\'m';
  }

  String _formatPercent(num value) {
    final rounded = value.abs() < 10
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(0);
    return '${value > 0 ? '+' : ''}$rounded%';
  }

  String _periodName(ReportPeriod period) => switch (period) {
    ReportPeriod.daily => _tr('reports.daily', 'Kunlik'),
    ReportPeriod.weekly => _tr('reports.weekly', 'Haftalik'),
    ReportPeriod.monthly => _tr('reports.monthly', 'Oylik'),
    ReportPeriod.yearly => _tr('reports.yearly', 'Yillik'),
  };

  String _periodSubtitle(ReportPeriod period) => switch (period) {
    ReportPeriod.daily => _tr(
      'reports.daily_comparison',
      'Kecha vs Bugungi kun',
    ),
    ReportPeriod.weekly => _tr(
      'reports.weekly_comparison',
      'O\'tgan hafta vs Bu hafta',
    ),
    ReportPeriod.monthly => _tr(
      'reports.monthly_comparison',
      'O\'tgan oy vs Bu oy',
    ),
    ReportPeriod.yearly => _tr(
      'reports.yearly_comparison',
      'O\'tgan yil vs Bu yil',
    ),
  };

  String _comparisonSuffix(ReportPeriod period) => switch (period) {
    ReportPeriod.daily => _tr('reports.daily_suffix', 'kechaga nisbatan'),
    ReportPeriod.weekly => _tr(
      'reports.weekly_suffix',
      'o\'tgan haftaga nisbatan',
    ),
    ReportPeriod.monthly => _tr(
      'reports.monthly_suffix',
      'o\'tgan oyga nisbatan',
    ),
    ReportPeriod.yearly => _tr(
      'reports.yearly_suffix',
      'o\'tgan yilga nisbatan',
    ),
  };

  String _comparisonLabel(ReportPeriod period, {required bool previous}) {
    final key = switch ((period, previous)) {
      (ReportPeriod.daily, true) => 'reports.yesterday',
      (ReportPeriod.daily, false) => 'reports.today',
      (ReportPeriod.weekly, true) => 'reports.last_week',
      (ReportPeriod.weekly, false) => 'reports.this_week',
      (ReportPeriod.monthly, true) => 'reports.last_month',
      (ReportPeriod.monthly, false) => 'reports.this_month',
      (ReportPeriod.yearly, true) => 'reports.last_year',
      (ReportPeriod.yearly, false) => 'reports.this_year',
    };
    final fallback = switch ((period, previous)) {
      (ReportPeriod.daily, true) => 'Kecha',
      (ReportPeriod.daily, false) => 'Bugun',
      (ReportPeriod.weekly, true) => 'O\'tgan hafta',
      (ReportPeriod.weekly, false) => 'Bu hafta',
      (ReportPeriod.monthly, true) => 'O\'tgan oy',
      (ReportPeriod.monthly, false) => 'Bu oy',
      (ReportPeriod.yearly, true) => 'O\'tgan yil',
      (ReportPeriod.yearly, false) => 'Bu yil',
    };
    return _tr(key, fallback);
  }

  void _scrollToPeriod(ReportPeriod period) {
    final target = _sectionKeys[period]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  Widget _buildSection(ReportPeriod period, int sectionNumber) {
    final now = DateTime.now();
    final window = SalesReportCalculator.windowFor(period, now);
    final current = SalesReportCalculator.aggregate(
      _sales,
      window.currentStart,
      window.currentEnd,
    );
    final previous = SalesReportCalculator.aggregate(
      _sales,
      window.previousStart,
      window.previousEnd,
    );
    final buckets = SalesReportCalculator.bucketSales(period, _sales, window);

    final isDark = ThemeController.instance.isDarkMode;
    final textColor = isDark
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF172033);
    final mutedTextColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE7ECF3);
    final surface = isDark ? const Color(0xFF172033) : Colors.white;
    final previousLabel = _comparisonLabel(period, previous: true);
    final currentLabel = _comparisonLabel(period, previous: false);
    final comparison = _comparisonSuffix(period);

    return Container(
      key: _sectionKeys[period],
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.035),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$sectionNumber. ${_periodName(period)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _periodSubtitle(period),
                      style: TextStyle(fontSize: 11, color: mutedTextColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PeriodSelector(
                period: period,
                label: _periodName(period),
                periods: _periods,
                periodLabel: _periodName,
                onSelected: _scrollToPeriod,
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 760
                  ? 3
                  : width >= 500
                  ? 2
                  : 1;
              final gap = 10.0;
              final cardWidth = (width - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _MetricCard(
                    width: cardWidth,
                    title: _tr('reports.turnover', 'Aylanma foyda'),
                    value: _formatMoney(current.turnover),
                    change: SalesReportCalculator.percentageChange(
                      previous.turnover,
                      current.turnover,
                    ),
                    isIncreasing: current.turnover > previous.turnover,
                    isDecreasing: current.turnover < previous.turnover,
                    comparison: comparison,
                    icon: Icons.shopping_cart_outlined,
                    color: const Color(0xFF1688E8),
                    isDark: isDark,
                    formatPercent: _formatPercent,
                  ),
                  _MetricCard(
                    width: cardWidth,
                    title: _tr('reports.net_profit', 'Sof foyda'),
                    value: _formatMoney(current.netProfit),
                    change: SalesReportCalculator.percentageChange(
                      previous.netProfit,
                      current.netProfit,
                    ),
                    isIncreasing: current.netProfit > previous.netProfit,
                    isDecreasing: current.netProfit < previous.netProfit,
                    comparison: comparison,
                    icon: Icons.account_balance_wallet_outlined,
                    color: const Color(0xFF8B5CF6),
                    isDark: isDark,
                    formatPercent: _formatPercent,
                  ),
                  _MetricCard(
                    width: cardWidth,
                    title: _tr('reports.sold_products', 'Sotilgan mahsulotlar'),
                    value: NumberFormat.decimalPattern(
                      'uz_UZ',
                    ).format(current.soldProducts),
                    change: SalesReportCalculator.percentageChange(
                      previous.soldProducts,
                      current.soldProducts,
                    ),
                    isIncreasing: current.soldProducts > previous.soldProducts,
                    isDecreasing: current.soldProducts < previous.soldProducts,
                    comparison: comparison,
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFFF59E0B),
                    isDark: isDark,
                    formatPercent: _formatPercent,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _GroupedComparisonChart(
            buckets: buckets,
            previousLabel: previousLabel,
            currentLabel: currentLabel,
            turnoverPrevious: _turnoverPrevious,
            turnoverCurrent: _turnoverCurrent,
            profitPrevious: _profitPrevious,
            profitCurrent: _profitCurrent,
            isDark: isDark,
            formatCompact: _formatCompact,
          ),
        ],
      ),
    );
  }

  String _formatCompact(num value) {
    final abs = value.abs();
    if (abs >= 1000000000) return '${(value / 1000000000).toStringAsFixed(0)}B';
    if (abs >= 1000000) return '${(value / 1000000).toStringAsFixed(0)}M';
    if (abs >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final _ = context.locale;
    final isDark = ThemeController.instance.isDarkMode;
    return ColoredBox(
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF7F9FC),
      child: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: isDark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF2563EB),
              ),
            )
          : _error != null
          ? Center(
              child: Text(
                _tr(
                  'reports.load_error',
                  'Hisobot ma\'lumotlarini yuklab bo\'lmadi',
                ),
                style: const TextStyle(color: Color(0xFFEF4444)),
              ),
            )
          : SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (var i = 0; i < _periods.length; i++)
                    _buildSection(_periods[i], i + 1),
                ],
              ),
            ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.period,
    required this.label,
    required this.periods,
    required this.periodLabel,
    required this.onSelected,
    required this.isDark,
  });

  final ReportPeriod period;
  final String label;
  final List<ReportPeriod> periods;
  final String Function(ReportPeriod) periodLabel;
  final ValueChanged<ReportPeriod> onSelected;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE6EAF0),
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ReportPeriod>(
          value: period,
          isDense: true,
          iconSize: 15,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF172033),
          ),
          items: [
            for (final item in periods)
              DropdownMenuItem(value: item, child: Text(periodLabel(item))),
          ],
          onChanged: (value) {
            if (value != null) onSelected(value);
          },
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.title,
    required this.value,
    required this.change,
    required this.isIncreasing,
    required this.isDecreasing,
    required this.comparison,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.formatPercent,
  });

  final double width;
  final String title;
  final String value;
  final num change;
  final bool isIncreasing;
  final bool isDecreasing;
  final String comparison;
  final IconData icon;
  final Color color;
  final bool isDark;
  final String Function(num) formatPercent;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF172033);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final trendColor = isIncreasing
        ? const Color(0xFF16A36A)
        : isDecreasing
        ? const Color(0xFFEF4444)
        : muted;
    return Container(
      width: width,
      height: 86,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE8EDF3),
        ),
        borderRadius: BorderRadius.circular(9),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.025),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: muted),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      isIncreasing
                          ? Icons.trending_up_rounded
                          : isDecreasing
                          ? Icons.trending_down_rounded
                          : Icons.trending_flat_rounded,
                      size: 13,
                      color: trendColor,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      formatPercent(change),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: trendColor,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        comparison,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupedComparisonChart extends StatelessWidget {
  const _GroupedComparisonChart({
    required this.buckets,
    required this.previousLabel,
    required this.currentLabel,
    required this.turnoverPrevious,
    required this.turnoverCurrent,
    required this.profitPrevious,
    required this.profitCurrent,
    required this.isDark,
    required this.formatCompact,
  });

  final List<ReportBucket> buckets;
  final String previousLabel;
  final String currentLabel;
  final Color turnoverPrevious;
  final Color turnoverCurrent;
  final Color profitPrevious;
  final Color profitCurrent;
  final bool isDark;
  final String Function(num) formatCompact;

  @override
  Widget build(BuildContext context) {
    final values = <num>[
      for (final bucket in buckets) ...[
        bucket.previous.turnover,
        bucket.current.turnover,
        bucket.previous.netProfit,
        bucket.current.netProfit,
      ],
    ];
    final positiveMax = values.fold<num>(0, (a, b) => math.max(a, b));
    final negativeMin = values.fold<num>(0, (a, b) => math.min(a, b));
    final maxY = positiveMax == 0 ? 1.0 : (positiveMax * 1.18).toDouble();
    final minY = negativeMin == 0 ? 0.0 : (negativeMin * 1.18).toDouble();
    final interval = math.max((maxY - minY) / 4, 0.25);
    final chartText = isDark ? const Color(0xFFE2E8F0) : Colors.black;
    final barWidth = buckets.length >= 12 ? 5.0 : 7.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111B2D) : const Color(0xFFFCFDFE),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFEDF1F5),
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              _LegendItem(
                color: turnoverPrevious,
                label: '${'reports.turnover_legend'.tr()} ($previousLabel)',
                textColor: chartText,
              ),
              _LegendItem(
                color: turnoverCurrent,
                label: '${'reports.turnover_legend'.tr()} ($currentLabel)',
                textColor: chartText,
              ),
              _LegendItem(
                color: profitPrevious,
                label: '${'reports.net_profit'.tr()} ($previousLabel)',
                textColor: chartText,
              ),
              _LegendItem(
                color: profitCurrent,
                label: '${'reports.net_profit'.tr()} ($currentLabel)',
                textColor: chartText,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: buckets.length > 10 ? 178 : 188,
            child: BarChart(
              BarChartData(
                minY: minY,
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                groupsSpace: 10,
                barGroups: [
                  for (var index = 0; index < buckets.length; index++)
                    BarChartGroupData(
                      x: index,
                      barsSpace: 1,
                      barRods: [
                        BarChartRodData(
                          toY: buckets[index].previous.turnover.toDouble(),
                          color: turnoverPrevious,
                          width: barWidth,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        BarChartRodData(
                          toY: buckets[index].current.turnover.toDouble(),
                          color: turnoverCurrent,
                          width: barWidth,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        BarChartRodData(
                          toY: buckets[index].previous.netProfit.toDouble(),
                          color: profitPrevious,
                          width: barWidth,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        BarChartRodData(
                          toY: buckets[index].current.netProfit.toDouble(),
                          color: profitCurrent,
                          width: barWidth,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    ),
                ],
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval.toDouble(),
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: isDark
                        ? const Color(0xFF263449)
                        : const Color(0xFFEDF1F5),
                    strokeWidth: 1,
                    dashArray: [3, 3],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: interval.toDouble(),
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        space: 5,
                        child: Text(
                          formatCompact(value),
                          style: TextStyle(fontSize: 10, color: chartText),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 27,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (value != index ||
                            index < 0 ||
                            index >= buckets.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          space: 5,
                          child: Text(
                            buckets[index].label,
                            maxLines: 1,
                            style: TextStyle(fontSize: 10, color: chartText),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(enabled: true),
              ),
              duration: const Duration(milliseconds: 250),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.textColor,
  });

  final Color color;
  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10, color: textColor)),
      ],
    );
  }
}

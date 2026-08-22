import re

with open('lib/screens/finance_page.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Replace _MonthlyPoint class with _ChartPoint
old_monthly_point_class = """class _MonthlyPoint {
  final int monthIndex;
  final String monthLabel;
  final num incoming;
  final num outgoing;
  final num profit;
  final num debt;

  _MonthlyPoint({
    required this.monthIndex,
    required this.monthLabel,
    required this.incoming,
    required this.outgoing,
    required this.profit,
    required this.debt,
  });
}"""
new_chart_point_class = """class _ChartPoint {
  final int index;
  final DateTime date;
  final String monthLabel;
  final num incoming;
  final num outgoing;
  final num profit;
  final num debt;
  final bool isStartOfMonth;

  _ChartPoint({
    required this.index,
    required this.date,
    required this.monthLabel,
    required this.incoming,
    required this.outgoing,
    required this.profit,
    required this.debt,
    this.isStartOfMonth = false,
  });
}"""
code = code.replace(old_monthly_point_class, new_chart_point_class)

# 2. Add debt to _PeriodBucket
old_period_bucket = """  int outgoingQty = 0;
  num outgoingCost = 0;
  num outgoingSales = 0;
  num outgoingProfit = 0;
  final outgoingProductIds = <String>{};
}"""
new_period_bucket = """  int outgoingQty = 0;
  num outgoingCost = 0;
  num outgoingSales = 0;
  num outgoingProfit = 0;
  final outgoingProductIds = <String>{};
  num debt = 0;
}"""
code = code.replace(old_period_bucket, new_period_bucket)

# 3. State variables
old_state_vars = """  List<_ActionLogEntry> _actionLogs = const [];
  List<_MonthlyPoint> _monthlyPoints = const [];
  List<_WeekDayPoint> _weekDayPoints = const [];"""
new_state_vars = """  List<_ActionLogEntry> _actionLogs = const [];
  List<_ChartPoint> _chartPoints = const [];
  Map<String, _MMAcc> _monthBuckets = {};
  List<_WeekDayPoint> _weekDayPoints = const [];"""
code = code.replace(old_state_vars, new_state_vars)

# 4. Generate 6 months instead of 12
old_month_keys = """    final monthKeysOrdered = <String>[];
    for (int i = 11; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final mk = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      monthKeysOrdered.add(mk);
      monthBuckets[mk] = _MMAcc();
    }"""
new_month_keys = """    final monthKeysOrdered = <String>[];
    final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final mk = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      monthKeysOrdered.add(mk);
      monthBuckets[mk] = _MMAcc();
    }"""
code = code.replace(old_month_keys, new_month_keys)

# 5. processEntries incoming loop
old_inc_loop = """        dayBucket.incomingQty += safeQty;
        dayBucket.incomingValue += safeValue;
        dayBucket.incomingProductIds.add(productId);"""
new_inc_loop = """        dayBucket.incomingQty += safeQty;
        dayBucket.incomingValue += safeValue;
        if (isDebtPurchase) dayBucket.debt -= safeValue;
        dayBucket.incomingProductIds.add(productId);"""
code = code.replace(old_inc_loop, new_inc_loop)

# 6. processEntries outgoing loop
old_out_loop = """        dayBucket.outgoingQty += safeQty;
        dayBucket.outgoingCost += safeCost;
        dayBucket.outgoingSales += safeSale;
        dayBucket.outgoingProfit += totalProfit;
        dayBucket.outgoingProductIds.add(productId);"""
new_out_loop = """        dayBucket.outgoingQty += safeQty;
        dayBucket.outgoingCost += safeCost;
        dayBucket.outgoingSales += safeSale;
        dayBucket.outgoingProfit += totalProfit;
        if (isDebtSale) dayBucket.debt -= safeSale;
        else dayBucket.debt += safeSale;
        dayBucket.outgoingProductIds.add(productId);"""
code = code.replace(old_out_loop, new_out_loop)

# 7. Generate chartPoints instead of monthly
old_monthly_gen = """    final monthly = <_MonthlyPoint>[];
    for (int i = 0; i < monthKeysOrdered.length; i++) {
      final mk = monthKeysOrdered[i];
      final parts = mk.split('-');
      final month = int.parse(parts[1]);
      final b = monthBuckets[mk] ?? _MMAcc();
      monthly.add(_MonthlyPoint(
        monthIndex: i,
        monthLabel: monthLabels[month - 1],
        incoming: b.incoming,
        outgoing: b.outgoing,
        profit: b.profit,
        debt: b.debt,
      ));
    }"""
new_monthly_gen = """    final chartPoints = <_ChartPoint>[];
    DateTime currentD = sixMonthsAgo;
    int index = 0;
    while (!currentD.isAfter(now)) {
      final dk = _dayKey(currentD);
      final b = dayBuckets[dk];
      final isStartOfMonth = currentD.day == 1 || index == 0;

      chartPoints.add(_ChartPoint(
        index: index,
        date: currentD,
        monthLabel: monthLabels[currentD.month - 1],
        incoming: b?.incomingValue ?? 0,
        outgoing: b?.outgoingSales ?? 0,
        profit: b?.outgoingProfit ?? 0,
        debt: b?.debt ?? 0,
        isStartOfMonth: isStartOfMonth,
      ));
      currentD = currentD.add(const Duration(days: 1));
      index++;
    }"""
code = code.replace(old_monthly_gen, new_monthly_gen)

# 8. Set state updates
old_set_state = """        _actionLogs = List.unmodifiable(logs);
        _monthlyPoints = List.unmodifiable(monthly);
        _weekDayPoints = List.unmodifiable(weekDayPoints);"""
new_set_state = """        _actionLogs = List.unmodifiable(logs);
        _chartPoints = List.unmodifiable(chartPoints);
        _monthBuckets = monthBuckets;
        _weekDayPoints = List.unmodifiable(weekDayPoints);"""
code = code.replace(old_set_state, new_set_state)

# 9. _buildMonthlyLineChart logic changes
code = code.replace('if (_monthlyPoints.isEmpty) {', 'if (_chartPoints.isEmpty) {')
code = code.replace('for (final p in _monthlyPoints) {', 'for (final p in _chartPoints) {')
code = code.replace('for (int i = 0; i < _monthlyPoints.length; i++) {', 'for (int i = 0; i < _chartPoints.length; i++) {')
code = code.replace('final p = _monthlyPoints[i];', 'final p = _chartPoints[i];')
code = code.replace('maxX: (_monthlyPoints.length - 1).toDouble(),', 'maxX: (_chartPoints.length - 1).toDouble(),')

# Tooltip / touch data updates
old_idx_check = """                      if (idx < 0 || idx >= _monthlyPoints.length) {
                        final roundIdx = first.x.round();
                        if (roundIdx >= 0 && roundIdx < _monthlyPoints.length) {
                          idx = roundIdx;
                        }
                      }
                      if (idx < 0 || idx >= _monthlyPoints.length) return;
                      final p = _monthlyPoints[idx];
                      final monthName = p.monthLabel.length == 3 && p.monthIndex >= 0 && p.monthIndex < 12
                          ? monthFullTitles[p.monthIndex]
                          : p.monthLabel;
                      _showMonthStatsModal(p, monthName);"""
new_idx_check = """                      if (idx < 0 || idx >= _chartPoints.length) {
                        final roundIdx = first.x.round();
                        if (roundIdx >= 0 && roundIdx < _chartPoints.length) {
                          idx = roundIdx;
                        }
                      }
                      if (idx < 0 || idx >= _chartPoints.length) return;
                      final p = _chartPoints[idx];
                      final dateStr = '${p.date.day.toString().padLeft(2, '0')}.${p.date.month.toString().padLeft(2, '0')}.${p.date.year}';
                      _showStatsModal(
                        incoming: p.incoming,
                        outgoing: p.outgoing,
                        profit: p.profit,
                        debt: p.debt,
                        title: dateStr,
                        subtitle: _t('finance.modal_day_subtitle', 'Kun bo\\'yicha statistika'),
                      );"""
code = code.replace(old_idx_check, new_idx_check)

old_tooltip_check = """                      if (idx < 0 || idx >= _monthlyPoints.length) {
                        final roundIdx = first.x.round();
                        if (roundIdx >= 0 && roundIdx < _monthlyPoints.length) {
                          idx = roundIdx;
                        }
                      }
                      if (idx < 0 || idx >= _monthlyPoints.length) return [];
                      final p = _monthlyPoints[idx];
                      final monthName = p.monthLabel.length == 3 && p.monthIndex >= 0 && p.monthIndex < 12
                          ? monthFullTitles[p.monthIndex]
                          : p.monthLabel;"""
new_tooltip_check = """                      if (idx < 0 || idx >= _chartPoints.length) {
                        final roundIdx = first.x.round();
                        if (roundIdx >= 0 && roundIdx < _chartPoints.length) {
                          idx = roundIdx;
                        }
                      }
                      if (idx < 0 || idx >= _chartPoints.length) return [];
                      final p = _chartPoints[idx];
                      final monthName = '${p.date.day.toString().padLeft(2, '0')}.${p.date.month.toString().padLeft(2, '0')}.${p.date.year}';"""
code = code.replace(old_tooltip_check, new_tooltip_check)


# 10. Update X-axis titles in bottomTitles
old_bottom_titles = """                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= monthTitles.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(monthTitles[i], style: titlesStyle),
                        );
                      },
                    ),
                  ),"""

new_bottom_titles = """                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= _chartPoints.length) return const SizedBox.shrink();
                        final p = _chartPoints[i];
                        if (!p.isStartOfMonth) return const SizedBox.shrink();

                        return GestureDetector(
                          onTap: () {
                            final mk = '${p.date.year}-${p.date.month.toString().padLeft(2, '0')}';
                            final mb = _monthBuckets[mk] ?? _MMAcc();
                            final monthName = monthFullTitles[p.date.month - 1];
                            _showStatsModal(
                              incoming: mb.incoming,
                              outgoing: mb.outgoing,
                              profit: mb.profit,
                              debt: mb.debt,
                              title: monthName,
                              subtitle: _t('finance.modal_month_subtitle', 'Oy bo\\'yicha statistika'),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(p.monthLabel, style: titlesStyle.copyWith(decoration: TextDecoration.underline)),
                          ),
                        );
                      },
                    ),
                  ),"""
code = code.replace(old_bottom_titles, new_bottom_titles)

# 11. Rename monthTitles usage since we removed it
code = code.replace('final monthTitles = <String>[];\n', '')
code = code.replace('final shortLabel = p.monthLabel.isNotEmpty ? p.monthLabel : monthLabels[i % 12];\n      monthTitles.add(\'$shortLabel $daysInMonth\');', '')

# 12. Fix _showMonthStatsModal declaration
old_modal_def = """  void _showMonthStatsModal(_MonthlyPoint p, String monthName) {"""
new_modal_def = """  void _showStatsModal({
    required num incoming,
    required num outgoing,
    required num profit,
    required num debt,
    required String title,
    required String subtitle,
  }) {"""
code = code.replace(old_modal_def, new_modal_def)

code = code.replace('final isProfit = p.profit >= 0;', 'final isProfit = profit >= 0;')
code = code.replace('_statRow(color: cIncoming, label: _t(\'finance.modal_incoming\', \'Omborga kirim (sotish narxi)\'), amount: p.incoming)', '_statRow(color: cIncoming, label: _t(\'finance.modal_incoming\', \'Omborga kirim (sotish narxi)\'), amount: incoming)')
code = code.replace('_statRow(color: cOutgoing, label: _t(\'finance.modal_outgoing\', \'Sotuv summasi (chiqim)\'), amount: p.outgoing)', '_statRow(color: cOutgoing, label: _t(\'finance.modal_outgoing\', \'Sotuv summasi (chiqim)\'), amount: outgoing)')
code = code.replace('_statRow(color: profitColor, label: _t(\'finance.modal_profit\', isProfit ? \'Jami foyda\' : \'Jami zarar\'), amount: p.profit, amountColor: profitColor)', '_statRow(color: profitColor, label: _t(\'finance.modal_profit\', isProfit ? \'Jami foyda\' : \'Jami zarar\'), amount: profit, amountColor: profitColor)')
code = code.replace('_statRow(color: cDebt, label: _t(\'finance.modal_debt\', \'Jami qarz\'), amount: p.debt)', '_statRow(color: cDebt, label: _t(\'finance.modal_debt\', \'Jami qarz\'), amount: debt)')

code = code.replace('monthName,', 'title,')
code = code.replace('_t(\'finance.modal_month_subtitle\', \'Oy bo\\\'yicha statistika\'),', 'subtitle,')

# 13. Replace text '12 oylik statistika' with '6 oylik statistika'
code = code.replace("'12 oylik statistika'", "'6 oylik statistika'")
code = code.replace("_t('finance.chart.title_year'", "_t('finance.chart.title_half_year'")


with open('lib/screens/finance_page.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Done")

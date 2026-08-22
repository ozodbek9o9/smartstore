import re

with open('lib/screens/finance_page.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update month generation in _processEntries
old_month_keys = """    final monthKeysOrdered = <String>[];
    final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final mk = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      monthKeysOrdered.add(mk);
      monthBuckets[mk] = _MMAcc();
    }"""
new_month_keys = """    final monthKeysOrdered = <String>[];
    final startMonth = DateTime(now.year, now.month - 2, 1);
    for (int i = -2; i <= 3; i++) {
      final m = DateTime(now.year, now.month + i, 1);
      final mk = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      monthKeysOrdered.add(mk);
      monthBuckets[mk] = _MMAcc();
    }"""
code = code.replace(old_month_keys, new_month_keys)

# 2. Update chartPoints generation in _processEntries
old_chart_points_loop = """    final chartPoints = <_ChartPoint>[];
    DateTime currentD = sixMonthsAgo;
    int index = 0;"""
new_chart_points_loop = """    final chartPoints = <_ChartPoint>[];
    DateTime currentD = startMonth;
    int index = 0;"""
code = code.replace(old_chart_points_loop, new_chart_points_loop)

# 3. Add totalDays and startMonth in _buildMonthlyLineChart
# We need to find `for (int i = 0; i < _chartPoints.length; i++) {`
old_chart_points_build_loop = """    for (int i = 0; i < _chartPoints.length; i++) {"""
new_chart_points_build_loop = """    final now = DateTime.now();
    final startMonth = DateTime(now.year, now.month - 2, 1);
    final endMonth = DateTime(now.year, now.month + 4, 0);
    final totalDays = endMonth.difference(startMonth).inDays;
    for (int i = 0; i < _chartPoints.length; i++) {"""
code = code.replace(old_chart_points_build_loop, new_chart_points_build_loop)

# 4. Update maxX in _buildMonthlyLineChart
old_maxx = """maxX: (_chartPoints.length - 1).toDouble(),"""
new_maxx = """maxX: totalDays.toDouble(),"""
code = code.replace(old_maxx, new_maxx)

# 5. Hide dots
old_dot_data = """        dotData: FlDotData(
          show: true,"""
new_dot_data = """        dotData: FlDotData(
          show: false,"""
code = code.replace(old_dot_data, new_dot_data)

# 6. Update bottomTitles to calculate future month labels
# The old getTitlesWidget:
old_bottom_titles = """                  bottomTitles: AxisTitles(
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
                              subtitle: _t('finance.modal_month_subtitle', "Oy bo'yicha statistika"),
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
new_bottom_titles = """                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i > totalDays) return const SizedBox.shrink();
                        
                        final d = startMonth.add(Duration(days: i));
                        if (d.day != 1 && i != 0) return const SizedBox.shrink();
                        
                        final shortMonthNames = [
                          _t('finance.month.short.1', 'Yan'), _t('finance.month.short.2', 'Fev'), _t('finance.month.short.3', 'Mar'),
                          _t('finance.month.short.4', 'Apr'), _t('finance.month.short.5', 'May'), _t('finance.month.short.6', 'Iyn'),
                          _t('finance.month.short.7', 'Iyl'), _t('finance.month.short.8', 'Avg'), _t('finance.month.short.9', 'Sen'),
                          _t('finance.month.short.10', 'Okt'), _t('finance.month.short.11', 'Noy'), _t('finance.month.short.12', 'Dek')
                        ];

                        return GestureDetector(
                          onTap: () {
                            final mk = '${d.year}-${d.month.toString().padLeft(2, '0')}';
                            final mb = _monthBuckets[mk] ?? _MMAcc();
                            final monthName = monthFullTitles[d.month - 1];
                            _showStatsModal(
                              incoming: mb.incoming,
                              outgoing: mb.outgoing,
                              profit: mb.profit,
                              debt: mb.debt,
                              title: monthName,
                              subtitle: _t('finance.modal_month_subtitle', "Oy bo'yicha statistika"),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(shortMonthNames[d.month - 1], style: titlesStyle.copyWith(decoration: TextDecoration.underline)),
                          ),
                        );
                      },
                    ),
                  ),"""
code = code.replace(old_bottom_titles, new_bottom_titles)

with open('lib/screens/finance_page.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Done")

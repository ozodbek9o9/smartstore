import re

with open('lib/screens/analytics_page.dart', 'r', encoding='utf-8') as f:
    code = f.read()


# 1. Update Customer Debt logic
old_debt_logic = """      final ledgerRemaining = debts - payments;
      final total = ledgerRemaining.abs() > 0 ? ledgerRemaining : rawDebt;"""
new_debt_logic = """      final hasLedger = (_customerDebts[c.id]?.isNotEmpty ?? false) || (_customerPayments[c.id]?.isNotEmpty ?? false);
      final ledgerRemaining = debts - payments;
      final total = hasLedger ? ledgerRemaining : rawDebt;"""
code = code.replace(old_debt_logic, new_debt_logic)


# 2. Update _aggregateRange logic for incoming
old_incoming_agg = """      if (type == 'incoming') {
        final totalValue = _parseNum(d['totalValue']);
        final safeQty = quantity < 0 ? 0 : quantity;
        final safeValue = totalValue < 0 ? 0 : totalValue;
        final sign = isDebtPurchase ? -1 : 1;
        totals.incomingQty += safeQty;
        totals.incomingValue += sign * safeValue;
        if (includeDaily) {
          totals.daily[dayIdx]!.incoming += safeValue;
          totals.hourly[ts.hour]!.incoming += safeValue;
        }
      }"""
new_incoming_agg = """      if (type == 'incoming') {
        final totalValue = _parseNum(d['totalValue']);
        final safeQty = quantity;
        final safeValue = totalValue;
        totals.incomingQty += safeQty;
        totals.incomingValue += safeValue;
        if (includeDaily) {
          totals.daily[dayIdx]!.incoming += safeValue;
          totals.hourly[ts.hour]!.incoming += safeValue;
        }
      }"""
code = code.replace(old_incoming_agg, new_incoming_agg)

# 3. Update _aggregateRange logic for outgoing
old_outgoing_agg = """      } else if (type == 'outgoing') {
        final totalCost = _parseNum(d['totalCostValue']);
        final totalSale = _parseNum(d['totalSaleValue']);
        final totalProfit = _parseNum(d['totalProfit']);
        final safeQty = quantity < 0 ? 0 : quantity;
        final safeCost = totalCost < 0 ? 0 : totalCost;
        final safeSale = totalSale < 0 ? 0 : totalSale;
        final sign = isDebtSale ? -1 : 1;
        final signedSale = sign * safeSale;
        final signedProfit = sign * totalProfit;

        totals.outgoingQty += safeQty;
        totals.outgoingCost += sign * safeCost;
        totals.outgoingSales += signedSale;
        totals.outgoingProfit += signedProfit;
        if (saleId.isNotEmpty) saleIds.add(saleId);
        if (customerId.isNotEmpty) customerIds.add(customerId);

        if (includeDaily) {
          totals.daily[dayIdx]!.revenue += signedSale;
          totals.daily[dayIdx]!.profit += signedProfit;
          totals.daily[dayIdx]!.salesCount += 1;
          totals.hourly[ts.hour]!.revenue += signedSale;
          totals.hourly[ts.hour]!.profit += signedProfit;
          totals.hourly[ts.hour]!.salesCount += 1;
        }
        totals.weekdayAgg[weekday]!.revenue += safeSale;
        totals.weekdayAgg[weekday]!.profit += totalProfit;
        totals.weekdayAgg[weekday]!.salesCount += 1;"""

new_outgoing_agg = """      } else if (type == 'outgoing') {
        final totalCost = _parseNum(d['totalCostValue']);
        final totalSale = _parseNum(d['totalSaleValue']);
        final totalProfit = _parseNum(d['totalProfit']);
        final safeQty = quantity;
        final safeCost = totalCost;
        final safeSale = totalSale;

        totals.outgoingQty += safeQty;
        totals.outgoingCost += safeCost;
        totals.outgoingSales += safeSale;
        totals.outgoingProfit += totalProfit;
        if (saleId.isNotEmpty) saleIds.add(saleId);
        if (customerId.isNotEmpty) customerIds.add(customerId);

        if (includeDaily) {
          totals.daily[dayIdx]!.revenue += safeSale;
          totals.daily[dayIdx]!.profit += totalProfit;
          totals.daily[dayIdx]!.salesCount += 1;
          totals.hourly[ts.hour]!.revenue += safeSale;
          totals.hourly[ts.hour]!.profit += totalProfit;
          totals.hourly[ts.hour]!.salesCount += 1;
        }
        totals.weekdayAgg[weekday]!.revenue += safeSale;
        totals.weekdayAgg[weekday]!.profit += totalProfit;
        totals.weekdayAgg[weekday]!.salesCount += 1;"""
code = code.replace(old_outgoing_agg, new_outgoing_agg)


with open('lib/screens/analytics_page.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Analytics done")

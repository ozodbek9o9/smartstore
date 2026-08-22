import re

with open('lib/screens/finance_page.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Incoming logic fixes (Negative clamps removed)
old_incoming = """      if (type == 'incoming') {
        final totalValue = parseNum(data['totalValue']);
        final safeQty = quantity < 0 ? 0 : quantity;
        final safeValue = totalValue < 0 ? 0 : totalValue;
        final safeSellingValue =
            (sellingPrice < 0 ? 0 : sellingPrice) * safeQty;"""
new_incoming = """      if (type == 'incoming') {
        final totalValue = parseNum(data['totalValue']);
        final safeQty = quantity;
        final safeValue = totalValue;
        final safeSellingValue = sellingPrice * safeQty;"""
code = code.replace(old_incoming, new_incoming)


# 2. Outgoing logic fixes (Negative clamps removed)
old_outgoing = """      } else if (type == 'outgoing') {
        final totalCost = parseNum(data['totalCostValue']);
        final totalSale = parseNum(data['totalSaleValue']);
        final totalProfit = parseNum(data['totalProfit']);
        final safeQty = quantity < 0 ? 0 : quantity;
        final safeCost = totalCost < 0 ? 0 : totalCost;
        final safeSale = totalSale < 0 ? 0 : totalSale;
        final sign = isDebtSale ? -1 : 1;"""
new_outgoing = """      } else if (type == 'outgoing') {
        final totalCost = parseNum(data['totalCostValue']);
        final totalSale = parseNum(data['totalSaleValue']);
        final totalProfit = parseNum(data['totalProfit']);
        final safeQty = quantity;
        final safeCost = totalCost;
        final safeSale = totalSale;
        final sign = 1;"""
code = code.replace(old_outgoing, new_outgoing)

# 3. Debt logic fixes in Outgoing Bucket Aggregation
old_bucket = """        dayBucket.outgoingProfit += totalProfit;
        if (isDebtSale)
          dayBucket.debt -= safeSale;
        else
          dayBucket.debt += safeSale;
        dayBucket.outgoingProductIds.add(productId);
        weekBucket.outgoingQty += safeQty;
        weekBucket.outgoingCost += safeCost;
        weekBucket.outgoingSales += safeSale;
        weekBucket.outgoingProfit += totalProfit;
        weekBucket.outgoingProductIds.add(productId);
        if (mBucket != null) {
          mBucket.outgoing += safeSale;
          mBucket.profit += totalProfit;
          if (isDebtSale) {
            mBucket.debt -= safeSale;
          } else {
            mBucket.debt += safeSale;
          }
        }"""
new_bucket = """        dayBucket.outgoingProfit += totalProfit;
        if (isDebtSale) {
          dayBucket.debt += safeSale;
        }
        dayBucket.outgoingProductIds.add(productId);
        weekBucket.outgoingQty += safeQty;
        weekBucket.outgoingCost += safeCost;
        weekBucket.outgoingSales += safeSale;
        weekBucket.outgoingProfit += totalProfit;
        weekBucket.outgoingProductIds.add(productId);
        if (mBucket != null) {
          mBucket.outgoing += safeSale;
          mBucket.profit += totalProfit;
          if (isDebtSale) {
            mBucket.debt += safeSale;
          }
        }"""
code = code.replace(old_bucket, new_bucket)


with open('lib/screens/finance_page.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Finance done")

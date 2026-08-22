import re

with open('lib/screens/home_page.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update customerBalance logic
old_customer_balance = """    num customerBalance(_Document customer) {
      if (customer.data.containsKey('remainingDebt')) {
        return math.max(0, customer.number('remainingDebt'));
      }
      final debts = customerDebts[customer.id]?.fold<num>(
            0,
            (sum, debt) => sum + debt.number('amount'),
          ) ??
          0;
      final payments = customerPayments[customer.id]?.fold<num>(
            0,
            (sum, payment) => sum + payment.number('amount'),
          ) ??
          0;
      return math.max(0, debts - payments);
    }"""
new_customer_balance = """    num customerBalance(_Document customer) {
      if (customer.data.containsKey('remainingDebt')) {
        return customer.number('remainingDebt');
      }
      final debts = customerDebts[customer.id]?.fold<num>(
            0,
            (sum, debt) => sum + debt.number('amount'),
          ) ??
          0;
      final payments = customerPayments[customer.id]?.fold<num>(
            0,
            (sum, payment) => sum + payment.number('amount'),
          ) ??
          0;
      return debts - payments;
    }"""
code = code.replace(old_customer_balance, new_customer_balance)

# 2. Update todayRevenue logic
old_revenue = """      // Signed arithmetic for revenue: debt sales decrease revenue, cash sales increase it
      todayRevenue += (isDebt ? -amount : amount);"""
new_revenue = """      todayRevenue += amount;"""
code = code.replace(old_revenue, new_revenue)

# 3. Remove cashSales and cardSales variables in _calculate logic
old_vars = """    num cashSales = 0;
    num cardSales = 0;
    num debtSales = 0;

    for (final sale in sales) {
      final amount = sale.number(
        'totalAmount',
        fallback: sale
            .list('items')
            .fold<num>(
              0,
              (sum, item) =>
                  sum +
                  _asNum(
                    item['total'] ??
                        (_asNum(item['price']) * _asNum(item['quantity'])),
                  ),
            ),
      );
      if (sale.boolean('isDebtSale')) {
        debtSales += amount;
      } else {
        final pm = sale.text('paymentMethod', '').toLowerCase();
        if (pm == 'card' || pm == 'credit_card' || pm == 'plastik' || pm == 'karta') {
          cardSales += amount;
        } else if (pm == 'cash' || pm == 'naqt' || pm == 'naqd') {
          cashSales += amount;
        } else {
          final split = amount.toDouble();
          cashSales += (split * 0.62);
          cardSales += (split * 0.38);
        }
      }
    }"""
new_vars = """    num debtSales = 0;

    for (final sale in sales) {
      final amount = sale.number(
        'totalAmount',
        fallback: sale
            .list('items')
            .fold<num>(
              0,
              (sum, item) =>
                  sum +
                  _asNum(
                    item['total'] ??
                        (_asNum(item['price']) * _asNum(item['quantity'])),
                  ),
            ),
      );
      if (sale.boolean('isDebtSale')) {
        debtSales += amount;
      }
    }"""
code = code.replace(old_vars, new_vars)

# 4. Remove cashSales and cardSales from DashboardOverview constructor and class
old_overview = """class _DashboardOverview {
  const _DashboardOverview({
    required this.todayRevenue,
    required this.todayProfit,
    required this.todayOrders,
    required this.todayCustomers,
    required this.todayProductsAdded,
    required this.cashSales,
    required this.cardSales,
    required this.debtSales,
    required this.debtPayments,
    required this.remainingDebt,
    required this.bestSellingHour,
    required this.bestSellingCategory,
  });

  final num todayRevenue;
  final num todayProfit;
  final int todayOrders;
  final int todayCustomers;
  final int todayProductsAdded;
  final num cashSales;
  final num cardSales;
  final num debtSales;
  final num debtPayments;
  final num remainingDebt;
  final String bestSellingHour;
  final String bestSellingCategory;

  num get averageOrder => todayOrders == 0 ? 0 : todayRevenue / todayOrders;

  num get totalSales => cashSales + cardSales + debtSales;
"""
new_overview = """class _DashboardOverview {
  const _DashboardOverview({
    required this.todayRevenue,
    required this.todayProfit,
    required this.todayOrders,
    required this.todayCustomers,
    required this.todayProductsAdded,
    required this.debtSales,
    required this.debtPayments,
    required this.remainingDebt,
    required this.bestSellingHour,
    required this.bestSellingCategory,
  });

  final num todayRevenue;
  final num todayProfit;
  final int todayOrders;
  final int todayCustomers;
  final int todayProductsAdded;
  final num debtSales;
  final num debtPayments;
  final num remainingDebt;
  final String bestSellingHour;
  final String bestSellingCategory;

  num get averageOrder => todayOrders == 0 ? 0 : todayRevenue / todayOrders;

  num get totalSales => todayRevenue;
"""
code = code.replace(old_overview, new_overview)

# 5. Remove cashSales and cardSales passing
old_passing = """      todayCustomers: todayCustomers,
      todayProductsAdded: todayProductsAdded,
      cashSales: cashSales,
      cardSales: cardSales,
      debtSales: debtSales,"""
new_passing = """      todayCustomers: todayCustomers,
      todayProductsAdded: todayProductsAdded,
      debtSales: debtSales,"""
code = code.replace(old_passing, new_passing)

# 6. Remove _SalesDistribution widget reference
# I will just regex replace the _SalesDistribution(...) part in build method.
import re
code = re.sub(r'const SizedBox\(height: 16\),\s*_SalesDistribution\(\s*cash:\s*overview\.cashSales,\s*card:\s*overview\.cashSales,\s*debt:\s*overview\.debtSales,\s*total:\s*overview\.totalSales,\s*\),', '', code)

# 7. Remove the _SalesDistribution class entirely
code = re.sub(r'class _SalesDistribution extends StatelessWidget \{.*?\n\}\n(?=class _SalesChart)', '', code, flags=re.DOTALL)


with open('lib/screens/home_page.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Done")

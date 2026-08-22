import os
import re

path = r"lib/screens/home_page.dart"
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Clean _DebtSummary and remove _Legend
start_idx = text.find("class _DebtSummary extends StatelessWidget {")
end_idx = text.find("class _TopSellingProducts extends StatelessWidget {")

debt_summary_code = """class _DebtSummary extends StatelessWidget {
  const _DebtSummary({required this.overview});
  final _DashboardOverview overview;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final isWide = size.maxWidth >= 1100;
      final columns = isWide ? 4 : 2;
      
      final tiles = [
        _DebtTile(
          'Jami qarzlar',
          _money(overview.remainingDebt),
          '${overview.customersWithDebt} customer',
          Icons.account_balance_wallet_outlined,
          const Color(0xFFEF4444),
        ),
        _DebtTile(
          'Bugun to\\'langan',
          _money(overview.todayDebtPayments),
          '${overview.todayDebtPaymentsCount} ta to\\'lov',
          Icons.check_circle_outline_rounded,
          const Color(0xFF16A34A),
        ),
        _DebtTile(
          'Qarz to\\'lanishi kerak',
          _money(overview.remainingDebt),
          '${overview.customersWithDebt} ta qarzdor',
          Icons.access_time_rounded,
          const Color(0xFFF59E0B),
        ),
      ];
      
      return GridView.count(
        crossAxisCount: columns,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: columns == 4 ? 2.8 : 2.5,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: tiles,
      );
    },
  );
}

"""

if start_idx != -1 and end_idx != -1:
    text = text[:start_idx] + debt_summary_code + text[end_idx:]

# 2. Fix the const issues
text = text.replace("const Text(", "Text(")
text = text.replace("const TextStyle(", "TextStyle(")
text = text.replace("const Icon(", "Icon(")
text = text.replace("const BoxDecoration(", "BoxDecoration(")
text = text.replace("const Border(", "Border(")
text = text.replace("const BorderSide(", "BorderSide(")
text = text.replace("const Divider(", "Divider(")
text = text.replace("const EdgeInsets", "EdgeInsets")

with open(path, "w", encoding="utf-8") as f:
    f.write(text)

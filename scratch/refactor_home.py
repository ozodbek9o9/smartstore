import os
import re

path = r"lib/screens/home_page.dart"
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Add AppTheme class
app_theme = """
class AppTheme {
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color pageBackground(BuildContext context) => isDark(context) ? const Color(0xFF0F172A) : const Color(0xFFF3F6FE);
  static Color cardBorder(BuildContext context) => isDark(context) ? const Color(0xFF334155) : const Color(0xFFE6EBF3);
  static Color title(BuildContext context) => isDark(context) ? const Color(0xFFF1F5F9) : const Color(0xFF172033);
  static Color muted(BuildContext context) => isDark(context) ? const Color(0xFF94A3B8) : const Color(0xFF718096);
  static Color panel(BuildContext context) => isDark(context) ? const Color(0xFF1E293B) : Colors.white;
  static Color shadow(BuildContext context) => isDark(context) ? Colors.black.withOpacity(0.4) : const Color(0xFF334155).withOpacity(.03);
  
  static Color goldBg(BuildContext context) => isDark(context) ? const Color(0xFF42381A) : const Color(0xFFFFF7D6);
  static Color silverBg(BuildContext context) => isDark(context) ? const Color(0xFF2A2E35) : const Color(0xFFF1F3F6);
  static Color bronzeBg(BuildContext context) => isDark(context) ? const Color(0xFF3D2A1C) : const Color(0xFFFFEBDD);
  
  static Color medalBg(BuildContext context, int rank) {
    if (rank == 1) return goldBg(context);
    if (rank == 2) return silverBg(context);
    if (rank == 3) return bronzeBg(context);
    return Colors.transparent;
  }
}
"""
if "class AppTheme" not in text:
    text += app_theme

# 2. Replace static colors in _HomePageState
text = re.sub(
    r"class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin \{\s+static const _pageBackground = Color\(0xFFF3F6FE\);\s+static const _cardBorder = Color\(0xFFE6EBF3\);\s+static const _title = Color\(0xFF172033\);\s+static const _muted = Color\(0xFF718096\);",
    "class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {",
    text
)

text = text.replace("_HomePageState._pageBackground", "AppTheme.pageBackground(context)")
text = text.replace("_HomePageState._title", "AppTheme.title(context)")
text = text.replace("_HomePageState._muted", "AppTheme.muted(context)")
text = text.replace("_HomePageState._cardBorder", "AppTheme.cardBorder(context)")

# 3. Fix _Panel background and shadow
panel_regex = r"decoration: BoxDecoration\(\s+color: Colors\.white,\s+borderRadius: BorderRadius\.circular\(12\),\s+border: Border\.all\(color: _HomePageState\._cardBorder\),\s+boxShadow: \[\s+BoxShadow\(\s+color: const Color\(0xFF334155\)\.withOpacity\(\.03\),"
panel_repl = """decoration: BoxDecoration(
      color: AppTheme.panel(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.cardBorder(context)),
      boxShadow: [
        BoxShadow(
          color: AppTheme.shadow(context),"""
text = re.sub(panel_regex, panel_repl, text)

# 4. _BestProductTile colors
best_tile_regex = r"color: const Color\(0xFFF8FAFC\),\s+shape: BoxShape\.circle,\s+border: Border\.all\(color: const Color\(0xFFE2E8F0\)\),"
best_tile_repl = """color: AppTheme.pageBackground(context),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.cardBorder(context)),"""
text = re.sub(best_tile_regex, best_tile_repl, text)

# 5. Remove Pie chart from _DebtSummary
pie_chart_start = r"_Panel\(\s+padding: const EdgeInsets\.all\(16\),\s+child: Column\(\s+crossAxisAlignment: CrossAxisAlignment\.start,\s+children: \[\s+const Text\(\s+'To\\'lov turlari bo\\'yicha savdo'"
# We know the pie chart is the last element in the 'tiles' array.
# I will use a regex to match from _Panel( ... 'To\'lov turlari bo\'yicha savdo' ... ) to the end of the list.
# Actually simpler: replace everything from that _Panel down to the end of the tiles array.
# Let's find exactly the block.
debt_summary_block = r"(_DebtTile\(\s+'Qarz to\\'lanishi kerak',[\s\S]*?\),)\s+_Panel\([\s\S]*?To\\'lov turlari bo\\'yicha savdo[\s\S]*?_Legend\('Qarz', debt, total, const Color\(0xFFF59E0B\)\),\s+],\s+\),\s+\],\s+\),\s+\),\s+\],"
text = re.sub(debt_summary_block, r"\1\n      ];", text)

# 6. Make cards compact and layout correctly
text = text.replace("childAspectRatio: columns == 4 ? 2.35 : 2.7,", "childAspectRatio: columns == 4 ? 2.8 : 2.5,")
text = text.replace("childAspectRatio: columns == 4 ? 2.5 : 2.5,", "childAspectRatio: columns == 4 ? 2.8 : 2.5,")
# Also change _StatisticGrid and _DebtSummary width thresholds if needed?
# User wants "bitta qatorga 4ta card sig'ish kerak" (4 cards fit in one row).
# They already do if columns == 4.

# 7. Update _SalesRow medal colors
sales_row_medal = r"const medalColors = \[\s+Color\(0xFFFFF7D6\),\s+Color\(0xFFF1F3F6\),\s+Color\(0xFFFFEBDD\),\s+\];\s+const medalIcons = \['🥇', '🥈', '🥉'\];\s+final isMedal = rank <= 3;\s+return Container\(\s+margin: const EdgeInsets\.only\(bottom: 2\),\s+padding: const EdgeInsets\.symmetric\(horizontal: 10, vertical: 12\),\s+decoration: BoxDecoration\(\s+color: isMedal \? medalColors\[rank - 1\] : Colors\.transparent,"
sales_row_repl = """const medalIcons = ['🥇', '🥈', '🥉'];
    final isMedal = rank <= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: isMedal ? AppTheme.medalBg(context, rank) : Colors.transparent,"""
text = re.sub(sales_row_medal, sales_row_repl, text)

# Ensure _HomePageState._cardBorder was also completely removed from tabs
text = text.replace("dividerColor: const Color(0xFFE6EBF3)", "dividerColor: AppTheme.cardBorder(context)")
text = text.replace("const Border(bottom: BorderSide(color: _HomePageState._cardBorder))", "Border(bottom: BorderSide(color: AppTheme.cardBorder(context)))")
text = text.replace("const Divider(color: Color(0xFFF0F3F7), height: 1)", "Divider(color: AppTheme.cardBorder(context), height: 1)")

with open(path, "w", encoding="utf-8") as f:
    f.write(text)

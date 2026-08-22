import os

path = r"lib/screens/home_page.dart"
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

debt_tile_code = """
class _DebtTile extends StatelessWidget {
  _DebtTile(this.label, this.value, this.subLabel, this.icon, this.color);
  final String label, value, subLabel;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(.08),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(.2)),
          ),
          child: Icon(icon, size: 24, color: color),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.title(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.title(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.muted(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
"""

if "class _DebtTile" not in text:
    idx = text.find("class _TopSellingProducts extends StatelessWidget {")
    text = text[:idx] + debt_tile_code + "\n" + text[idx:]

text = text.replace("color: _pageBackground,", "color: AppTheme.pageBackground(context),")
text = text.replace("this.padding = EdgeInsets.all(20)", "this.padding = const EdgeInsets.all(20)")

# There is a line 652 with const_eval_method_invocation. 
# Let's just fix Tabs!
# tabs: const [ Tab(text: 'Bugun'), ... ] might have been turned to tabs: [ Tab(text: 'Bugun') ] by previous remove, but let's be safe.
# Actually, let's just let it be and see the exact errors.

with open(path, "w", encoding="utf-8") as f:
    f.write(text)

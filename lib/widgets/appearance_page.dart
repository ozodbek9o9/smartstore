import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:smart_store/screens/theme_controller.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  final List<Map<String, dynamic>> _languages = [
    {'code': 'English', 'locale': const Locale('en', 'US'), 'key': 'languages.english'},
    {'code': 'Russian', 'locale': const Locale('ru', 'RU'), 'key': 'languages.russian'},
    {'code': 'Uzbek', 'locale': const Locale('uz', 'UZ'), 'key': 'languages.uzbek'},
  ];

  String _selectedLanguageCode = 'English';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    ThemeController.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguageCode = prefs.getString('language') ?? 'English';
    });
  }

  Future<void> _saveLanguage(String code) async {
    final option = _languages.firstWhere((l) => l['code'] == code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', code);
    await context.setLocale(option['locale']);
    setState(() => _selectedLanguageCode = code);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDarkMode;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F4FF);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final hairline = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        title: Text('settings.card_appearance_title'.tr(), style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Language Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: hairline)),
                  child: Row(
                    children: [
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(color: const Color(0xFF0EA5E9), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.language, color: Colors.white),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('settings.language'.tr(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
                            Text('settings.language_desc'.tr(), style: TextStyle(color: textSecondary)),
                          ],
                        ),
                      ),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedLanguageCode,
                          dropdownColor: cardColor,
                          style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
                          onChanged: (val) { if (val != null) _saveLanguage(val); },
                          items: _languages.map((l) => DropdownMenuItem<String>(
                            value: l['code'],
                            child: Text(l['key'].toString().tr()),
                          )).toList(),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Theme Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: hairline)),
                  child: Row(
                    children: [
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(color: const Color(0xFF8B5CF6), borderRadius: BorderRadius.circular(14)),
                        child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: Colors.white),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('settings.appearance'.tr(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
                            Text(isDark ? 'settings.dark_on'.tr() : 'settings.light_on'.tr(), style: TextStyle(color: textSecondary)),
                          ],
                        ),
                      ),
                      Switch(
                        value: isDark,
                        activeThumbColor: const Color(0xFF2563EB),
                        onChanged: (_) => ThemeController.instance.toggle(),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

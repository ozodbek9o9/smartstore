import re

p = r'C:\Users\user\OneDrive\Desktop\SmartStore\smart_store\lib\screens\analytics_page.dart'
with open(p, 'r', encoding='utf-8') as f:
    text = f.read()

replacements = {
    "'Savdo dinamikasi'": "'analytics.sales_dynamics'.tr()",
    "'Foyda & Xarajat tahlili'": "'analytics.profit_cost_analysis'.tr()",
    "'Kategoriya samaradorligi'": "'analytics.category_performance'.tr()",
    "'Yaqinlashayotgan ogohlantirishlar'": "'analytics.upcoming_warnings'.tr()",
    "'Hammasi joyida, ogohlantirishlar yo\\'q'": "'analytics.no_warnings'.tr()",
    "'Bugun yangi buyurtmalar kutilmoqda'": "'analytics.new_orders_expected'.tr()",
    "'BETA'": "'analytics.beta'.tr()",
    "'Bugun'": "'analytics.today'.tr()",
    "'Hafta'": "'analytics.week'.tr()",
    "'Oy'": "'home.tab_month'.tr()",  # I'll use home.tab_month because 'Oy' translates to 'Bu oy' in home. Or I can use 'analytics.month'.tr() wait, analytics.month has 'Oy' in UZ.
    "'Foyda'": "'analytics.profit'.tr()",
    "'Sotuv'": "'analytics.sale'.tr()",
    "'Xarajat'": "'analytics.cost'.tr()",
    "'Omborga kirgan'": "'analytics.incoming'.tr()",
    "'vs oldingi'": "'analytics.vs_previous'.tr()",
    "'Joriy davr'": "'analytics.current_period'.tr()",
    "'Oldingi davr'": "'analytics.previous_period'.tr()",
    "'Malumot topilmadi'": "'analytics.no_data'.tr()",
    "'Omborga kirishni optimallashtiring'": "'analytics.optimize_incoming'.tr()",
    "'Qarzdorlarni eslatish'": "'analytics.remind_debtors'.tr()",
    "'Qarzdor mijozlarga to\\'lovni eslating'": "'analytics.remind_debtors_desc'.tr()",
    "'Kam sotiladigan mahsulotlar'": "'analytics.low_selling_products'.tr()",
    "'Kamroq olish kerak'": "'analytics.less_purchase'.tr()",
    "'Tavsiya'": "'analytics.recommendation'.tr()",
    "'Mijozlar'": "'analytics.customers'.tr()"
}

replacements["'Oy'"] = "'analytics.month'.tr()"

for k, v in replacements.items():
    text = text.replace(k, v)

with open(p, 'w', encoding='utf-8') as f:
    f.write(text)

print('analytics_page.dart updated')

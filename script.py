import json
import os
import re

base_dir = r'C:\Users\user\OneDrive\Desktop\SmartStore\smart_store'
translations_dir = os.path.join(base_dir, 'assets', 'translations')

uz_path = os.path.join(translations_dir, 'uz-UZ.json')
ru_path = os.path.join(translations_dir, 'ru-RU.json')
en_path = os.path.join(translations_dir, 'en-US.json')

def load_json(p):
    with open(p, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_json(p, data):
    with open(p, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

uz = load_json(uz_path)
ru = load_json(ru_path)
en = load_json(en_path)

# 1. Update 'home' block
home_uz = {
    "best_qty_sold": "Sotilgan soni",
    "warehouse_title": "Ombor holati",
    "warehouse_total": "Jami mahsulot turlari",
    "common_qty_unit": "ta",
    "common_days_unit": "kun",
    "activity_new_debt": "Yangi qarz qo'shildi",
    "lowest_col_sales": "Sotuv",
    "lowest_col_revenue": "Daromad",
    "best_revenue": "Daromad: {}"
}
home_ru = {
    "best_qty_sold": "Кол-во продаж",
    "warehouse_title": "Состояние склада",
    "warehouse_total": "Всего видов товаров",
    "common_qty_unit": "шт",
    "common_days_unit": "дн",
    "activity_new_debt": "Новый долг добавлен",
    "lowest_col_sales": "Продажи",
    "lowest_col_revenue": "Доход",
    "best_revenue": "Доход: {}"
}
home_en = {
    "best_qty_sold": "Qty Sold",
    "warehouse_title": "Warehouse Status",
    "warehouse_total": "Total Product Types",
    "common_qty_unit": "pcs",
    "common_days_unit": "days",
    "activity_new_debt": "New debt added",
    "lowest_col_sales": "Sales",
    "lowest_col_revenue": "Revenue",
    "best_revenue": "Revenue: {}"
}

for k, v in home_uz.items(): uz['home'][k] = v
for k, v in home_ru.items(): ru['home'][k] = v
for k, v in home_en.items(): en['home'][k] = v

# 2. Add 'analytics' block
uz['analytics'] = {
    "title": "Tahlil",
    "sales_dynamics": "Savdo dinamikasi",
    "profit_cost_analysis": "Foyda & Xarajat tahlili",
    "category_performance": "Kategoriya samaradorligi",
    "upcoming_warnings": "Yaqinlashayotgan ogohlantirishlar",
    "no_warnings": "Hammasi joyida, ogohlantirishlar yo'q",
    "new_orders_expected": "Bugun yangi buyurtmalar kutilmoqda",
    "beta": "BETA",
    "today": "Bugun",
    "week": "Hafta",
    "month": "Oy",
    "profit": "Foyda",
    "sale": "Sotuv",
    "cost": "Xarajat",
    "incoming": "Omborga kirgan",
    "vs_previous": "vs oldingi",
    "current_period": "Joriy davr",
    "previous_period": "Oldingi davr",
    "no_data": "Malumot topilmadi",
    "optimize_incoming": "Omborga kirishni optimallashtiring",
    "remind_debtors": "Qarzdorlarni eslatish",
    "remind_debtors_desc": "Qarzdor mijozlarga to'lovni eslating",
    "low_selling_products": "Kam sotiladigan mahsulotlar",
    "less_purchase": "Kamroq olish kerak",
    "recommendation": "Tavsiya",
    "customers": "Mijozlar"
}

ru['analytics'] = {
    "title": "Аналитика",
    "sales_dynamics": "Динамика продаж",
    "profit_cost_analysis": "Анализ прибыли и затрат",
    "category_performance": "Эффективность категорий",
    "upcoming_warnings": "Предстоящие предупреждения",
    "no_warnings": "Все в порядке, предупреждений нет",
    "new_orders_expected": "Сегодня ожидаются новые заказы",
    "beta": "БЕТА",
    "today": "Сегодня",
    "week": "Неделя",
    "month": "Месяц",
    "profit": "Прибыль",
    "sale": "Продажи",
    "cost": "Расход",
    "incoming": "Поступило на склад",
    "vs_previous": "по сравнению с пред.",
    "current_period": "Текущий период",
    "previous_period": "Предыдущий период",
    "no_data": "Данные не найдены",
    "optimize_incoming": "Оптимизируйте поступления",
    "remind_debtors": "Напомнить должникам",
    "remind_debtors_desc": "Напомните должникам об оплате",
    "low_selling_products": "Слабо продаваемые товары",
    "less_purchase": "Нужно покупать меньше",
    "recommendation": "Рекомендация",
    "customers": "Клиенты"
}

en['analytics'] = {
    "title": "Analytics",
    "sales_dynamics": "Sales Dynamics",
    "profit_cost_analysis": "Profit & Cost Analysis",
    "category_performance": "Category Performance",
    "upcoming_warnings": "Upcoming Warnings",
    "no_warnings": "All good, no warnings",
    "new_orders_expected": "New orders expected today",
    "beta": "BETA",
    "today": "Today",
    "week": "Week",
    "month": "Month",
    "profit": "Profit",
    "sale": "Sales",
    "cost": "Cost",
    "incoming": "Incoming to Warehouse",
    "vs_previous": "vs previous",
    "current_period": "Current period",
    "previous_period": "Previous period",
    "no_data": "No data found",
    "optimize_incoming": "Optimize Incoming",
    "remind_debtors": "Remind Debtors",
    "remind_debtors_desc": "Remind debtors to pay",
    "low_selling_products": "Low selling products",
    "less_purchase": "Should purchase less",
    "recommendation": "Recommendation",
    "customers": "Customers"
}

save_json(uz_path, uz)
save_json(ru_path, ru)
save_json(en_path, en)
print('JSON files updated.')

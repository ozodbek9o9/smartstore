import json
import os

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

# Update to include '{}' for placeholders
uz['home']['common_qty_unit'] = "{} ta"
uz['home']['common_days_unit'] = "{} kun"
uz['home']['best_qty_sold'] = "Sotilgan: {} dona"

ru['home']['common_qty_unit'] = "{} шт"
ru['home']['common_days_unit'] = "{} дн"
ru['home']['best_qty_sold'] = "Продано: {} шт"

en['home']['common_qty_unit'] = "{} pcs"
en['home']['common_days_unit'] = "{} days"
en['home']['best_qty_sold'] = "Sold: {} pcs"

save_json(uz_path, uz)
save_json(ru_path, ru)
save_json(en_path, en)
print('JSON files fixed for placeholders.')

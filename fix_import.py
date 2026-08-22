import re

p = r'C:\Users\user\OneDrive\Desktop\SmartStore\smart_store\lib\screens\analytics_page.dart'
with open(p, 'r', encoding='utf-8') as f:
    text = f.read()

if 'easy_localization' not in text:
    text = text.replace(
        "import 'package:flutter/material.dart';", 
        "import 'package:flutter/material.dart';\nimport 'package:easy_localization/easy_localization.dart';"
    )
    with open(p, 'w', encoding='utf-8') as f:
        f.write(text)
    print('Added easy_localization import')
else:
    print('already imported')

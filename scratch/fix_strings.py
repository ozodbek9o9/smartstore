import os

path = r"lib/screens/home_page.dart"
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

text = text.replace("\\\\'", "\\'")

with open(path, "w", encoding="utf-8") as f:
    f.write(text)

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stock delete confirmation translations exist in all locales', () async {
    final root = Directory.current.path;
    final files = [
      File('$root/assets/translations/en-US.json'),
      File('$root/assets/translations/ru-RU.json'),
      File('$root/assets/translations/uz-UZ.json'),
    ];

    for (final file in files) {
      expect(
        await file.exists(),
        isTrue,
        reason: 'Missing translation file: ${file.path}',
      );
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final stockPage = data['stock_page'] as Map<String, dynamic>;

      expect(
        stockPage['delete_confirm_title'],
        isNotNull,
        reason: 'Missing delete_confirm_title in ${file.path}',
      );
      expect(
        stockPage['delete_confirm_content'],
        isNotNull,
        reason: 'Missing delete_confirm_content in ${file.path}',
      );
      expect(
        stockPage['delete_confirm_cancel'],
        isNotNull,
        reason: 'Missing delete_confirm_cancel in ${file.path}',
      );
      expect(
        stockPage['delete_confirm_delete'],
        isNotNull,
        reason: 'Missing delete_confirm_delete in ${file.path}',
      );
    }
  });
}

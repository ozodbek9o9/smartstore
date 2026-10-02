import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';

class AccountCredentialSecurity {
  AccountCredentialSecurity._();

  static const _bcryptRounds = 12;
  static final _bcryptPattern = RegExp(r'^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$');

  static bool hasBcryptHash(String? value) =>
      value != null && _bcryptPattern.hasMatch(value);

  static Future<String> hashPassword(String password) {
    if (utf8.encode(password).length > 72) {
      throw ArgumentError('Bcrypt paroli 72 baytdan uzun bo\'lmasligi kerak.');
    }
    return compute(_hashPassword, password);
  }

  static Future<bool> verifyPassword(
    String password,
    Map<String, dynamic> account,
  ) async {
    final hash = account['passwordHash']?.toString();
    if (hash != null && hash.isNotEmpty) {
      if (!hasBcryptHash(hash)) return false;
      return compute(_verifyBcryptPassword, [password, hash]);
    }
    return account['password']?.toString() == password;
  }
}

String _hashPassword(String password) => BCrypt.hashpw(
  password,
  BCrypt.gensalt(logRounds: AccountCredentialSecurity._bcryptRounds),
);

bool _verifyBcryptPassword(List<String> values) {
  try {
    return BCrypt.checkpw(values[0], values[1]);
  } on ArgumentError {
    return false;
  }
}

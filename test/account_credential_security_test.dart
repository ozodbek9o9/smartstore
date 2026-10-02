import 'package:flutter_test/flutter_test.dart';
import 'package:smart_store/services/account_credential_security.dart';

void main() {
  test(
    'bcrypt hash verifies the password but not a different password',
    () async {
      const password = 'Strong-password-2026';
      final hash = await AccountCredentialSecurity.hashPassword(password);

      expect(AccountCredentialSecurity.hasBcryptHash(hash), isTrue);
      expect(hash, isNot(contains(password)));
      expect(
        await AccountCredentialSecurity.verifyPassword(password, {
          'passwordHash': hash,
        }),
        isTrue,
      );
      expect(
        await AccountCredentialSecurity.verifyPassword('wrong-password', {
          'passwordHash': hash,
        }),
        isFalse,
      );
    },
  );

  test(
    'legacy plaintext accounts remain verifiable before migration',
    () async {
      expect(
        await AccountCredentialSecurity.verifyPassword('legacy-password', {
          'password': 'legacy-password',
        }),
        isTrue,
      );
      expect(
        await AccountCredentialSecurity.verifyPassword('wrong-password', {
          'password': 'legacy-password',
        }),
        isFalse,
      );
    },
  );
}

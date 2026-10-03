import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_controller.dart';
import '../services/account_credential_security.dart';
import '../services/auth_service.dart';
import '../services/connected_devices_service.dart';
import '../widgets/connected_devices_card.dart';
import '../utils/tenant_firestore.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _credentialSecurityEnabled = false;
  String _loadedUsername = '';
  String _customerId = '';

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    _loadAccount();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    _fullNameController.dispose();
    _usernameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadAccount() async {
    try {
      final document = await TenantFirestore.userDocument.get();
      final data = document.data() ?? const <String, dynamic>{};
      _fullNameController.text = data['fullName']?.toString() ?? '';
      _loadedUsername = data['username']?.toString() ?? '';
      _usernameController.text = _loadedUsername;
      _customerId = data['customerId']?.toString() ?? '';
      _credentialSecurityEnabled = data['passwordProtectionEnabled'] == true;
      if (_customerId.isEmpty) {
        _credentialSecurityEnabled = true;
      } else {
        final customer = await FirebaseFirestore.instance
            .collection('customers')
            .doc(_customerId)
            .get();
        final customerData = customer.data() ?? const <String, dynamic>{};
        final existingHash = customerData['passwordHash']?.toString();
        _credentialSecurityEnabled =
            customerData['passwordProtectionEnabled'] == true ||
            (existingHash != null && existingHash.isNotEmpty);
      }
    } catch (error) {
      debugPrint('Unable to load settings: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.redAccent : const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final passwordWasChanged = _newPasswordController.text.isNotEmpty;
      final username = _usernameController.text.trim();
      final usernameWasChanged =
          username.toLowerCase() != _loadedUsername.toLowerCase();
      final credentialsWereChanged = usernameWasChanged || passwordWasChanged;

      if (credentialsWereChanged && _currentPasswordController.text.isEmpty) {
        _showMessage('Joriy parolni kiriting.', isError: true);
        return;
      }
      if (passwordWasChanged &&
          _newPasswordController.text != _confirmPasswordController.text) {
        _showMessage('account.err_passwords_mismatch'.tr(), isError: true);
        return;
      }

      if (_customerId.isNotEmpty) {
        final saved = await _saveCustomerAccount(
          username: username,
          fullName: _fullNameController.text,
          currentPassword: credentialsWereChanged
              ? _currentPasswordController.text
              : null,
          newPassword: passwordWasChanged ? _newPasswordController.text : null,
        );
        if (!saved) return;
      } else {
        await _authService.updateProfile(
          currentUsername: _loadedUsername,
          username: username,
          fullName: _fullNameController.text,
          currentPassword: credentialsWereChanged
              ? _currentPasswordController.text
              : null,
          newPassword: passwordWasChanged ? _newPasswordController.text : null,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', username);
      _loadedUsername = username;

      if (passwordWasChanged) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      } else if (credentialsWereChanged) {
        _currentPasswordController.clear();
      }

      if (mounted) setState(() {});
      _showMessage('account.success_saved'.tr());
    } catch (error) {
      if (error is InvalidUsernameException) {
        _showMessage(
          'Username kamida 3 ta belgi bo\'lsin: harf, raqam yoki _.',
          isError: true,
        );
        return;
      }
      if (error is UsernameAlreadyTakenException) {
        _showMessage('Bu username band. Boshqasini tanlang.', isError: true);
        return;
      }
      if (error is RecentAuthenticationRequiredException) {
        _showMessage('Joriy parolni kiriting.', isError: true);
        return;
      }
      _showMessage(
        'account.err_save'.tr(args: [error.toString()]),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _saveCustomerAccount({
    required String username,
    required String fullName,
    required String? currentPassword,
    required String? newPassword,
  }) async {
    final customerRef = FirebaseFirestore.instance
        .collection('customers')
        .doc(_customerId);
    final customerSnapshot = await customerRef.get();
    final customer = customerSnapshot.data();
    if (customer == null) {
      _showMessage('Customer ma’lumotlari topilmadi.', isError: true);
      return false;
    }

    if (currentPassword != null &&
        !await AccountCredentialSecurity.verifyPassword(
          currentPassword,
          customer,
        )) {
      _showMessage('Joriy parol noto‘g‘ri.', isError: true);
      return false;
    }

    if (username.toLowerCase() != _loadedUsername.toLowerCase()) {
      final duplicate = await FirebaseFirestore.instance
          .collection('customers')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      if (duplicate.docs.any((document) => document.id != _customerId)) {
        _showMessage('Bu username band. Boshqasini tanlang.', isError: true);
        return false;
      }
    }

    final customerUpdate = <String, dynamic>{
      'name': fullName.trim(),
      'username': username,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (newPassword != null && newPassword.isNotEmpty) {
      if (_credentialSecurityEnabled) {
        customerUpdate['passwordHash'] =
            await AccountCredentialSecurity.hashPassword(newPassword);
        customerUpdate['password'] = FieldValue.delete();
      } else {
        customerUpdate['password'] = newPassword;
        customerUpdate['passwordHash'] = FieldValue.delete();
      }
      customerUpdate['passwordProtectionEnabled'] = _credentialSecurityEnabled;
      customerUpdate['passwordUpdatedAt'] = FieldValue.serverTimestamp();
    }
    await customerRef.update(customerUpdate);
    await TenantFirestore.userDocument.set({
      'uid': TenantFirestore.uid,
      'username': username,
      'usernameLower': username.toLowerCase(),
      'fullName': fullName.trim(),
      'customerId': _customerId,
      'authProvider': 'anonymous_customer',
      'passwordProtectionEnabled': _credentialSecurityEnabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  Future<void> _setCredentialSecurity(bool enabled) async {
    if (!enabled) {
      _showMessage('account.security_cannot_disable'.tr(), isError: true);
      return;
    }
    if (_credentialSecurityEnabled || _isSaving) return;
    if (_customerId.isEmpty) {
      _showMessage('account.security_firebase_managed'.tr());
      return;
    }

    setState(() => _isSaving = true);
    try {
      final customerRef = FirebaseFirestore.instance
          .collection('customers')
          .doc(_customerId);
      final snapshot = await customerRef.get();
      final customer = snapshot.data();
      if (customer == null) {
        throw StateError('Customer ma’lumotlari topilmadi.');
      }

      final existingHash = customer['passwordHash']?.toString();
      final storedPassword = customer['password']?.toString();
      final hash = AccountCredentialSecurity.hasBcryptHash(existingHash)
          ? existingHash!
          : storedPassword == null || storedPassword.isEmpty
          ? throw StateError('Saqlangan parol topilmadi. Parolni yangilang.')
          : await AccountCredentialSecurity.hashPassword(storedPassword);

      final batch = FirebaseFirestore.instance.batch();
      batch.update(customerRef, {
        'passwordHash': hash,
        'password': FieldValue.delete(),
        'passwordProtectionEnabled': true,
        'passwordUpdatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(TenantFirestore.userDocument, {
        'passwordProtectionEnabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();

      if (mounted) setState(() => _credentialSecurityEnabled = true);
      _showMessage('account.security_enabled'.tr());
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _securitySwitch() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'account.security_title'.tr(),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      Switch.adaptive(
        value: _credentialSecurityEnabled,
        onChanged: _isSaving ? null : _setCredentialSecurity,
      ),
    ],
  );

  Future<void> _showDeleteAccountDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _DeleteAccountDialog(
        onDeleted: () {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/login');
          }
        },
        showMessage: _showMessage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDarkMode;
    final background = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF6F8FC);
    final cardColor = isDark ? const Color(0xFF182235) : Colors.white;
    final textPrimary = isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final inputColor = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF8FAFC);

    InputDecoration inputDecoration(
      String label,
      String hint,
      IconData icon, {
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: inputColor,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
        ),
      );
    }

    Widget passwordField({
      required TextEditingController controller,
      required String label,
      required String hint,
      required bool obscure,
      required ValueChanged<bool> onObscureChanged,
    }) {
      return TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: TextInputType.visiblePassword,
        style: TextStyle(color: textPrimary),
        decoration: inputDecoration(
          label,
          hint,
          Icons.lock_outline_rounded,
          suffixIcon: IconButton(
            tooltip: obscure
                ? 'account.show_password'.tr()
                : 'account.hide_password'.tr(),
            onPressed: () => onObscureChanged(!obscure),
            icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
      );
    }

    Widget sectionTitle(
      IconData icon,
      Color color,
      String title,
      String subtitle,
    ) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.2 : 0.11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: textSecondary),
                ),
              ],
            ),
          ),
        ],
      );
    }

    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Divider(height: 1, color: borderColor),
    );

    return ColoredBox(
      color: background,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1050),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'settings.title'.tr(),
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'settings.subtitle'.tr(),
                        style: TextStyle(color: textSecondary, fontSize: 15),
                      ),
                      const SizedBox(height: 24),
                      Card(
                        margin: EdgeInsets.zero,
                        color: cardColor,
                        surfaceTintColor: Colors.transparent,
                        elevation: isDark ? 0 : 5,
                        shadowColor: Colors.black.withOpacity(0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(color: borderColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 760;
                              Widget pair(Widget first, Widget second) => isWide
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: first),
                                        const SizedBox(width: 18),
                                        Expanded(child: second),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        first,
                                        const SizedBox(height: 16),
                                        second,
                                      ],
                                    );

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isWide)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: sectionTitle(
                                            Icons.person_rounded,
                                            const Color(0xFF4F46E5),
                                            'account.profile_title'.tr(),
                                            'account.profile_desc'.tr(),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        _securitySwitch(),
                                      ],
                                    )
                                  else ...[
                                    sectionTitle(
                                      Icons.person_rounded,
                                      const Color(0xFF4F46E5),
                                      'account.profile_title'.tr(),
                                      'account.profile_desc'.tr(),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: _securitySwitch(),
                                    ),
                                  ],
                                  const SizedBox(height: 22),
                                  pair(
                                    TextField(
                                      controller: _fullNameController,
                                      style: TextStyle(color: textPrimary),
                                      textCapitalization:
                                          TextCapitalization.words,
                                      decoration: inputDecoration(
                                        'account.full_name'.tr(),
                                        'account.enter_full_name'.tr(),
                                        Icons.badge_outlined,
                                      ),
                                    ),
                                    TextField(
                                      controller: _usernameController,
                                      style: TextStyle(color: textPrimary),
                                      decoration: inputDecoration(
                                        'account.username'.tr(),
                                        'account.enter_username'.tr(),
                                        Icons.alternate_email_rounded,
                                      ),
                                    ),
                                  ),
                                  divider(),
                                  sectionTitle(
                                    Icons.lock_rounded,
                                    const Color(0xFF059669),
                                    'account.password_title'.tr(),
                                    'account.password_desc'.tr(),
                                  ),
                                  const SizedBox(height: 22),
                                  pair(
                                    passwordField(
                                      controller: _currentPasswordController,
                                      label: 'Joriy parol',
                                      hint: 'Joriy parolni kiriting',
                                      obscure: _obscureCurrentPassword,
                                      onObscureChanged: (value) => setState(
                                        () => _obscureCurrentPassword = value,
                                      ),
                                    ),
                                    passwordField(
                                      controller: _newPasswordController,
                                      label: 'account.new_password'.tr(),
                                      hint: 'account.enter_new_password'.tr(),
                                      obscure: _obscureNewPassword,
                                      onObscureChanged: (value) => setState(
                                        () => _obscureNewPassword = value,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: isWide
                                          ? (constraints.maxWidth - 18) / 2
                                          : double.infinity,
                                    ),
                                    child: passwordField(
                                      controller: _confirmPasswordController,
                                      label: 'account.renew_password'.tr(),
                                      hint: 'account.reenter_new_password'.tr(),
                                      obscure: _obscureConfirmPassword,
                                      onObscureChanged: (value) => setState(
                                        () => _obscureConfirmPassword = value,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 26),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: _isSaving
                                            ? null
                                            : _saveChanges,
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 22,
                                            vertical: 16,
                                          ),
                                          backgroundColor: const Color(
                                            0xFF4F46E5,
                                          ),
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: _isSaving
                                            ? const SizedBox(
                                                height: 18,
                                                width: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(Icons.save_outlined),
                                        label: Text(
                                          'account.save_changes'.tr(),
                                        ),
                                      ),
                                    ],
                                  ),
                                  divider(),
                                  sectionTitle(
                                    Icons.delete_forever_rounded,
                                    const Color(0xFFEF4444),
                                    'account.delete_account_title'.tr(),
                                    'account.delete_account_desc'.tr(),
                                  ),
                                  const SizedBox(height: 22),
                                  OutlinedButton.icon(
                                    onPressed: _isSaving
                                        ? null
                                        : _showDeleteAccountDialog,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 16,
                                      ),
                                      foregroundColor: const Color(0xFFEF4444),
                                      side: const BorderSide(
                                        color: Color(0xFFEF4444),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.delete_forever_rounded,
                                    ),
                                    label: Text('account.delete_account'.tr()),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      ConnectedDevicesCard(
                        accountReference: _customerId.isNotEmpty
                            ? FirebaseFirestore.instance
                                  .collection('customers')
                                  .doc(_customerId)
                            : TenantFirestore.userDocument,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  final VoidCallback onDeleted;
  final void Function(String message, {bool isError}) showMessage;

  const _DeleteAccountDialog({
    required this.onDeleted,
    required this.showMessage,
  });

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  bool _agreed = false;
  bool _isDeleting = false;
  bool _obscurePassword = true;
  final _passwordController = TextEditingController();

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    final snapshot = await collection.get();
    for (var i = 0; i < snapshot.docs.length; i += 450) {
      final batch = FirebaseFirestore.instance.batch();
      final end = (i + 450 < snapshot.docs.length)
          ? i + 450
          : snapshot.docs.length;
      for (final doc in snapshot.docs.sublist(i, end)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _deleteUserFirestoreData() async {
    await ConnectedDevicesService().releaseCurrentDevice();
    final userRef = TenantFirestore.userDocument;
    final customers = await TenantFirestore.customers.get();

    final nestedDeletes = <Future<void>>[];
    for (final customer in customers.docs) {
      nestedDeletes.add(
        _deleteCollection(customer.reference.collection('debts')),
      );
      nestedDeletes.add(
        _deleteCollection(customer.reference.collection('payments')),
      );
    }
    await Future.wait(nestedDeletes);

    final collections = <CollectionReference<Map<String, dynamic>>>[
      TenantFirestore.products,
      TenantFirestore.customers,
      TenantFirestore.categories,
      TenantFirestore.sales,
      TenantFirestore.sellingCarts,
      TenantFirestore.draftProducts,
      TenantFirestore.settings,
      TenantFirestore.inventoryEntries,
      TenantFirestore.dailySummaries,
      TenantFirestore.weeklySummaries,
    ];
    await Future.wait(collections.map(_deleteCollection));
    await userRef.delete();
  }

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final textPrimary = isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0F172A);
    final textMuted = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final inputBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.error.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.delete_forever_rounded, color: colors.error),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'account.delete_dialog_title'.tr(),
              style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'account.delete_dialog_content'.tr(),
              style: TextStyle(color: textMuted),
            ),
            const SizedBox(height: 18),
            // Password re-authentication field
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              enabled: !_isDeleting,
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(
                labelText: 'account.current_password'.tr(),
                hintText: 'account.enter_current_password'.tr(),
                filled: true,
                fillColor: inputBg,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.error, width: 1.8),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_isDeleting) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
              Text(
                'Hisob va barcha ma\'lumotlar o\'chirilmoqda. Iltimos, kuting...',
                style: TextStyle(color: textMuted, fontSize: 12),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Checkbox(
                  value: _agreed,
                  onChanged: _isDeleting
                      ? null
                      : (value) => setState(() => _agreed = value ?? false),
                  activeColor: colors.error,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _isDeleting
                        ? null
                        : () => setState(() => _agreed = !_agreed),
                    child: Text(
                      'account.delete_dialog_agree'.tr(),
                      style: TextStyle(color: textPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context),
          child: Text('account.cancel'.tr()),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed:
              (!_agreed || _isDeleting || _passwordController.text.isEmpty)
              ? null
              : () async {
                  final startedAt = DateTime.now();
                  setState(() => _isDeleting = true);
                  try {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) throw Exception('Not logged in');

                    // Re-authenticate to satisfy Firebase's recent-login requirement
                    final email = user.email!;
                    final cred = EmailAuthProvider.credential(
                      email: email,
                      password: _passwordController.text,
                    );
                    await user.reauthenticateWithCredential(cred);

                    // Remove every user-owned document, including nested ledgers.
                    await _deleteUserFirestoreData();
                    await user.delete();

                    final elapsed = DateTime.now().difference(startedAt);
                    const minimumDuration = Duration(seconds: 5);
                    if (elapsed < minimumDuration) {
                      await Future<void>.delayed(minimumDuration - elapsed);
                    }

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();

                    if (mounted) {
                      Navigator.pop(context);
                      widget.onDeleted();
                    }
                  } on FirebaseAuthException catch (e) {
                    final msg =
                        e.code == 'wrong-password' ||
                            e.code == 'invalid-credential'
                        ? 'account.err_incorrect_password'.tr()
                        : e.message ?? e.toString();
                    widget.showMessage(msg, isError: true);
                    if (mounted) setState(() => _isDeleting = false);
                  } catch (e) {
                    widget.showMessage(e.toString(), isError: true);
                    if (mounted) setState(() => _isDeleting = false);
                  }
                },
          icon: _isDeleting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.delete_forever_rounded),
          label: Text(
            _isDeleting
                ? 'account.deleting'.tr()
                : 'account.delete_account'.tr(),
          ),
        ),
      ],
    );
  }
}

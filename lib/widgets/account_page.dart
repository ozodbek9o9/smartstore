import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:smart_store/screens/theme_controller.dart';
import '../utils/tenant_firestore.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  String _userId = '';

  // Profile Information
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayPasswordCtrl = TextEditingController();

  // Password
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _renewPasswordCtrl = TextEditingController();

  bool _obscureCurrentPass = true;
  bool _obscureNewPass = true;
  bool _obscureRenewPass = true;
  bool _obscureDisplayPass = true;

  String _dbPassword = '';

  @override
  void initState() {
    super.initState();
    _loadData();
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

  Future<void> _loadData() async {
    try {
      _userId = TenantFirestore.uid;

      if (_userId.isNotEmpty) {
        final doc = await TenantFirestore.userDocument.get();
        if (doc.exists) {
          final data = doc.data()!;
          _fullNameCtrl.text = data['fullName'] ?? '';
          _phoneCtrl.text = data['phone'] ?? '';
          _usernameCtrl.text = data['username'] ?? '';
          _dbPassword = data['password'] ?? '';
          _displayPasswordCtrl.text = _dbPassword;
        }
      }
    } catch (e) {
      debugPrint('Error loading account data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();

      // Update Firebase Data
      Map<String, dynamic> updateData = {};

      updateData['fullName'] = _fullNameCtrl.text.trim();
      updateData['phone'] = _phoneCtrl.text.trim();
      updateData['username'] = _usernameCtrl.text.trim();

      // Password Change Logic
      if (_newPasswordCtrl.text.isNotEmpty) {
        if (_currentPasswordCtrl.text != _dbPassword) {
          _showSnackBar('account.err_incorrect_password'.tr(), isError: true);
          return;
        }
        if (_newPasswordCtrl.text != _renewPasswordCtrl.text) {
          _showSnackBar('account.err_passwords_mismatch'.tr(), isError: true);
          return;
        }
        updateData['password'] = _newPasswordCtrl.text;
      }

      if (updateData.isNotEmpty && _userId.isNotEmpty) {
        await TenantFirestore.userDocument.set(
          updateData,
          SetOptions(merge: true),
        );
        if (updateData.containsKey('username')) {
          await prefs.setString('username', updateData['username']);
        }
        if (updateData.containsKey('password')) {
          _dbPassword = updateData['password'];
          _displayPasswordCtrl.text = _dbPassword;
          _currentPasswordCtrl.clear();
          _newPasswordCtrl.clear();
          _renewPasswordCtrl.clear();
        }
      }

      _showSnackBar('account.success_saved'.tr());
    } catch (e) {
      _showSnackBar('account.err_save'.tr(args: [e.toString()]), isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDarkMode;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F7FE);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final hairline = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textPrimary = isDark
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final inputBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    InputDecoration inputDecor(
      String hint,
      IconData prefixIcon, {
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Colors.grey[600] : Colors.grey[400],
          fontSize: 14,
        ),
        prefixIcon: Icon(
          prefixIcon,
          color: isDark ? Colors.grey[500] : Colors.grey[400],
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: inputBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4318FF), width: 1.5),
        ),
      );
    }

    Widget sectionHeader(
      IconData icon,
      Color iconColor,
      Color iconBg,
      String title,
      String subtitle, {
      Widget? trailing,
    }) {
      return Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: textSecondary),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      );
    }

    Widget inputLabel(String label) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0, top: 16),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        title: Text(
          'settings.card_account_title'.tr(),
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Profile Information Card ---
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            sectionHeader(
                              Icons.person,
                              const Color(0xFF4318FF),
                              const Color(0xFFF4F7FE),
                              'account.profile_title'.tr(),
                              'account.profile_desc'.tr(),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4F7FE),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.edit,
                                      size: 14,
                                      color: Color(0xFF4318FF),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'account.edit'.tr(),
                                      style: const TextStyle(
                                        color: Color(0xFF4318FF),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      inputLabel('account.full_name'.tr()),
                                      TextField(
                                        controller: _fullNameCtrl,
                                        style: TextStyle(color: textPrimary),
                                        decoration: inputDecor(
                                          'account.enter_full_name'.tr(),
                                          Icons.person_outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      inputLabel('account.phone'.tr()),
                                      TextField(
                                        controller: _phoneCtrl,
                                        style: TextStyle(color: textPrimary),
                                        decoration: inputDecor(
                                          'account.enter_phone'.tr(),
                                          Icons.phone_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      inputLabel('account.username'.tr()),
                                      TextField(
                                        controller: _usernameCtrl,
                                        style: TextStyle(color: textPrimary),
                                        decoration: inputDecor(
                                          'account.enter_username'.tr(),
                                          Icons.person_outline,
                                          suffixIcon: const Icon(
                                            Icons.edit,
                                            size: 18,
                                            color: Color(0xFF4318FF),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      inputLabel(
                                        'account.current_password'.tr(),
                                      ),
                                      TextField(
                                        controller: _displayPasswordCtrl,
                                        readOnly: true,
                                        obscureText: _obscureDisplayPass,
                                        style: TextStyle(color: textPrimary),
                                        decoration: inputDecor(
                                          'account.enter_current_password'.tr(),
                                          Icons.lock_outline,
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _obscureDisplayPass
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscureDisplayPass =
                                                  !_obscureDisplayPass,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // --- Password Card ---
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            sectionHeader(
                              Icons.lock,
                              const Color(0xFF05CD99),
                              const Color(0xFFE6FAF5),
                              'account.password_title'.tr(),
                              'account.password_desc'.tr(),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      inputLabel(
                                        'account.current_password'.tr(),
                                      ),
                                      TextField(
                                        controller: _currentPasswordCtrl,
                                        obscureText: _obscureCurrentPass,
                                        style: TextStyle(color: textPrimary),
                                        decoration: inputDecor(
                                          'account.enter_current_password'.tr(),
                                          Icons.lock_outline,
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _obscureCurrentPass
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscureCurrentPass =
                                                  !_obscureCurrentPass,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      inputLabel('account.new_password'.tr()),
                                      TextField(
                                        controller: _newPasswordCtrl,
                                        obscureText: _obscureNewPass,
                                        style: TextStyle(color: textPrimary),
                                        decoration: inputDecor(
                                          'account.enter_new_password'.tr(),
                                          Icons.lock_outline,
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _obscureNewPass
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscureNewPass =
                                                  !_obscureNewPass,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      inputLabel('account.renew_password'.tr()),
                                      TextField(
                                        controller: _renewPasswordCtrl,
                                        obscureText: _obscureRenewPass,
                                        style: TextStyle(color: textPrimary),
                                        decoration: inputDecor(
                                          'account.reenter_new_password'.tr(),
                                          Icons.lock_outline,
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _obscureRenewPass
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscureRenewPass =
                                                  !_obscureRenewPass,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                const Expanded(child: SizedBox()),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Save Button
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 200,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _saveChanges,
                            icon: const Icon(Icons.lock, size: 18),
                            label: _isSaving
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(
                                    'account.save_changes'.tr(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4318FF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

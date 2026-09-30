import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:smart_store/screens/stock_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_store/screens/theme_controller.dart';
import '../main.dart' show SmartStoreColors;
import '../utils/notification_controller.dart';
import '../utils/tenant_firestore.dart';
import 'home_page.dart';
import 'selling_page.dart';
import 'adding_page.dart';
import 'customers_page.dart';
import 'finance_page.dart';
import 'analytics_page.dart';
import 'settings_page.dart';

// ───────────────────────────────────────────────────────────────
// LayoutPage - Main Layout with Collapsible Sidebar
// ───────────────────────────────────────────────────────────────
class LayoutPage extends StatefulWidget {
  const LayoutPage({super.key});

  @override
  State<LayoutPage> createState() => _LayoutPageState();
}

enum _Section {
  home,
  selling,
  adding,
  stock,
  customers,
  finance,
  analytics,
  settings,
}

class _LayoutPageState extends State<LayoutPage> with TickerProviderStateMixin {
  _Section _selectedSection = _Section.home;
  bool _isSidebarOpen = true;
  bool _isOnline = true;
  bool _offlineDialogShowing = false;
  bool _isUserBlocked = false;
  bool _isRedirectingToLogin = false;
  bool _isHandlingBlockedAccount = false;
  Timer? _connectivityTimer;
  StreamSubscription<dynamic>? _accountStatusSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _customerStatusSubscription;
  StreamSubscription<User?>? _authStateSubscription;

  late AnimationController _sidebarController;
  late Animation<double> _sidebarAnimation;

  // Light mode colors
  static const Color _lightPageBg = Color(0xFFF0F4FF);
  static const Color _lightHairline = Color(0xFFE2E8F0);
  static const Color _lightSidebar = Colors.white;
  static const Color _lightTopBar = Colors.white;

  // Sidebar widths
  static const double _sidebarExpandedWidth = 264;
  static const double _sidebarCollapsedWidth =
      84; // widened to fit larger icon without overflow

  @override
  void initState() {
    super.initState();
    _startConnectivityCheck();
    unawaited(_watchAccountStatus());
    _watchAuthenticationState();
    _sidebarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1,
    );
    _sidebarAnimation = CurvedAnimation(
      parent: _sidebarController,
      curve: Curves.easeInOut,
    );
    ThemeController.instance.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _watchAccountStatus() async {
    if (_accountStatusSubscription != null) return;
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.authStateChanges().firstWhere(
        (user) => user != null,
      );
      if (!mounted) return;
    }
    if (_accountStatusSubscription != null) return;

    _accountStatusSubscription = TenantFirestore.userDocument
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) {
            _handleDeletedAccount();
            return;
          }

          final data = snapshot.data();
          final isBlocked = _isBlocked(data);

          if (mounted && isBlocked != _isUserBlocked) {
            setState(() => _isUserBlocked = isBlocked);
          }

          final customerId = data?['customerId']?.toString();
          if (customerId != null && customerId.isNotEmpty) {
            _watchCustomerStatus(customerId);
          }
        });
  }

  bool _isBlocked(Map<String, dynamic>? data) {
    final status = data?['status']?.toString().trim().toLowerCase();
    return data?['isBlocked'] == true ||
        data?['blocked'] == true ||
        data?['is_blocked'] == true ||
        status == 'blocked' ||
        status == 'block' ||
        status == 'bloklangan';
  }

  void _watchCustomerStatus(String customerId) {
    if (_customerStatusSubscription != null) return;

    _customerStatusSubscription = FirebaseFirestore.instance
        .collection('customers')
        .doc(customerId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) return;
          final isBlocked = _isBlocked(snapshot.data());
          if (!isBlocked) {
            if (mounted && _isUserBlocked) {
              setState(() => _isUserBlocked = false);
            }
            return;
          }
          _handleBlockedAccount();
        });
  }

  Future<void> _handleBlockedAccount() async {
    if (_isHandlingBlockedAccount || !mounted) return;
    _isHandlingBlockedAccount = true;
    setState(() => _isUserBlocked = true);
  }

  Future<void> _returnToLoginFromBlockedAccount() async {
    if (!mounted) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _handleDeletedAccount() async {
    if (_isRedirectingToLogin || !mounted) return;
    _isRedirectingToLogin = true;
    _accountStatusSubscription?.cancel();

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Navigation must still continue if the local sign-out request fails.
    }

    if (!mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _startConnectivityCheck() {
    _checkConnectivity();
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkConnectivity(),
    );
  }

  void _watchAuthenticationState() {
    _authStateSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      if (user == null && _accountStatusSubscription != null) {
        _handleDeletedAccount();
      }
    });
  }

  Future<void> _checkConnectivity() async {
    bool online;
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 4));
      online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      online = false;
    }

    if (online == _isOnline) return;
    setState(() => _isOnline = online);

    if (!online) {
      _showOfflineReminder();
    } else if (_offlineDialogShowing && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      _offlineDialogShowing = false;
    }
  }

  void _showOfflineReminder() {
    if (_offlineDialogShowing || !mounted) return;
    _offlineDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OfflineReminderDialog(
        onRetry: () async {
          Navigator.of(context, rootNavigator: true).pop();
          _offlineDialogShowing = false;
          await _checkConnectivity();
          if (!_isOnline) _showOfflineReminder();
        },
      ),
    ).then((_) => _offlineDialogShowing = false);
  }

  void toggleSidebar() {
    if (_isSidebarOpen) {
      _sidebarController.reverse();
    } else {
      _sidebarController.forward();
    }
    setState(() => _isSidebarOpen = !_isSidebarOpen);
  }

  void navigateToSection(_Section section) {
    setState(() => _selectedSection = section);
  }

  Future<void> logout() async {
    final isDark = ThemeController.instance.isDarkMode;
    bool isLoggingOut = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final confirmButton = SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: isLoggingOut
                  ? null
                  : () async {
                      setDialogState(() => isLoggingOut = true);

                      try {
                        final navigator = Navigator.of(
                          context,
                          rootNavigator: true,
                        );
                        final currentUser = FirebaseAuth.instance.currentUser;

                        if (currentUser == null) {
                          if (navigator.mounted) {
                            navigator.pushNamedAndRemoveUntil(
                              '/login',
                              (route) => false,
                            );
                          }
                          return;
                        }

                        await FirebaseAuth.instance.signOut();
                        if (navigator.mounted) {
                          navigator.pushNamedAndRemoveUntil(
                            '/login',
                            (route) => false,
                          );
                        }
                      } catch (_) {
                        setDialogState(() => isLoggingOut = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Chiqish vaqtida xatolik yuz berdi.',
                              ),
                              backgroundColor: SmartStoreColors.danger,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: SmartStoreColors.danger,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isLoggingOut
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Chiqilmoqda...',
                            style: TextStyle(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    )
                  : Text(
                      'logout_dialog.confirm'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          );

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 360,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: isDark ? SmartStoreColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDark
                      ? SmartStoreColors.darkDivider
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                    blurRadius: 30,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: SmartStoreColors.danger.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: SmartStoreColors.danger.withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: SmartStoreColors.danger,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'logout_dialog.title'.tr(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? SmartStoreColors.darkTextPrimary
                          : SmartStoreColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'logout_dialog.content'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? SmartStoreColors.darkTextSecondary
                          : SmartStoreColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: TextButton(
                            onPressed: isLoggingOut
                                ? null
                                : () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isDark
                                      ? SmartStoreColors.darkDivider
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                            child: Text(
                              'logout_dialog.cancel'.tr(),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? SmartStoreColors.darkTextSecondary
                                    : SmartStoreColors.lightTextSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: confirmButton),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Translation Helper with Fallback ──
  String _tr(String key, String fallback) {
    final val = key.tr();
    return (val == key || val.isEmpty) ? fallback : val;
  }

  // ── Support Center Dialog ──
  void _showSupportCenterDialog() {
    final isDark = ThemeController.instance.isDarkMode;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? SmartStoreColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? SmartStoreColors.darkDivider
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
                blurRadius: 36,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header Row ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0EA5E9).withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr('support_dialog.title', 'Support Center'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? SmartStoreColors.darkTextPrimary
                                : SmartStoreColors.lightTextPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _tr(
                            'support_dialog.subtitle',
                            'Need help or have questions? Get in touch with us anytime.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? SmartStoreColors.darkTextMuted
                                : SmartStoreColors.lightTextMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? SmartStoreColors.darkSurfaceVariant
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: isDark
                            ? SmartStoreColors.darkTextSecondary
                            : SmartStoreColors.lightTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── Build by Developer Badge ──
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.code_rounded,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _tr(
                          'support_dialog.build_by',
                          'Build by: Ozodbek Inomjonov',
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFF93C5FD)
                              : const Color(0xFF1E40AF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Contact Section Title ──
              Row(
                children: [
                  Icon(
                    Icons.connect_without_contact_rounded,
                    size: 18,
                    color: isDark
                        ? SmartStoreColors.darkTextSecondary
                        : SmartStoreColors.lightTextSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _tr('support_dialog.contact', 'Contact'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? SmartStoreColors.darkTextSecondary
                          : SmartStoreColors.lightTextSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Email Item ──
              _SupportContactTile(
                isDark: isDark,
                icon: Icons.email_rounded,
                iconGradient: const [Color(0xFFEA4335), Color(0xFFC5221F)],
                title: _tr('support_dialog.email', 'Email'),
                value: 'ozodbekinomjonov9o9@gmail.com',
                subtitle: _tr(
                  'support_dialog.email_sub',
                  'Click to write email',
                ),
                onTap: () => launchContactUrl(
                  context,
                  url: 'mailto:ozodbekinomjonov9o9@gmail.com',
                  copyFallback: 'ozodbekinomjonov9o9@gmail.com',
                ),
              ),

              const SizedBox(height: 10),

              // ── Phone Item ──
              _SupportContactTile(
                isDark: isDark,
                icon: Icons.phone_in_talk_rounded,
                iconGradient: const [Color(0xFF34A853), Color(0xFF1E8E3E)],
                title: _tr('support_dialog.phone', 'Phone'),
                value: '+998 50 155 18 09',
                subtitle: _tr('support_dialog.phone_sub', 'Click to call'),
                onTap: () => launchContactUrl(
                  context,
                  url: 'tel:+998501551809',
                  copyFallback: '+998501551809',
                ),
              ),

              const SizedBox(height: 10),

              // ── Telegram Item ──
              _SupportContactTile(
                isDark: isDark,
                icon: Icons.send_rounded,
                iconGradient: const [Color(0xFF29B6F6), Color(0xFF0288D1)],
                title: _tr('support_dialog.telegram', 'Telegram'),
                value: '@ozodbek_9o9',
                subtitle: _tr(
                  'support_dialog.telegram_sub',
                  'Click to open Telegram profile',
                ),
                onTap: () => launchContactUrl(
                  context,
                  url: 'https://t.me/ozodbek_9o9',
                  copyFallback: 'https://t.me/ozodbek_9o9',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> launchContactUrl(
    BuildContext context, {
    required String url,
    required String copyFallback,
  }) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        await copyToClipboard(context, copyFallback);
      }
    } catch (_) {
      if (mounted) {
        await copyToClipboard(context, copyFallback);
      }
    }
  }

  Future<void> copyToClipboard(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    final msg = _tr('support_dialog.copied', 'Copied to clipboard!');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$msg ($text)'),
        backgroundColor: SmartStoreColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Notifications Dialog ──
  void _showNotificationsDialog() {
    final isDark = ThemeController.instance.isDarkMode;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? SmartStoreColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? SmartStoreColors.darkDivider
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
                blurRadius: 36,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ListenableBuilder(
            listenable: NotificationController.instance,
            builder: (context, _) {
              final alerts = NotificationController.instance.alerts;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header Row ──
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Color(0xFFEF4444),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _tr('notifications.title', 'Notifications'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? SmartStoreColors.darkTextPrimary
                                : SmartStoreColors.lightTextPrimary,
                          ),
                        ),
                      ),
                      if (alerts.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            NotificationController.instance.markAllAsRead();
                          },
                          icon: const Icon(
                            Icons.done_all_rounded,
                            size: 16,
                            color: Color(0xFF0284C7),
                          ),
                          label: Text(
                            _tr(
                              'notifications.mark_all_read',
                              'All mark as read',
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? SmartStoreColors.darkSurfaceVariant
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: isDark
                                ? SmartStoreColors.darkTextSecondary
                                : SmartStoreColors.lightTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Divider(
                    color: isDark
                        ? SmartStoreColors.darkDivider
                        : const Color(0xFFE2E8F0),
                  ),
                  const SizedBox(height: 12),

                  if (alerts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 48,
                            color: isDark
                                ? Colors.grey.shade600
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _tr(
                              'notifications.no_notifications',
                              'No new notifications',
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? SmartStoreColors.darkTextMuted
                                  : SmartStoreColors.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: alerts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final alert = alerts[index];
                          final formattedDebt = _formatCurrencyNum(
                            alert.remainingDebt,
                          );
                          final dateStr = _formatDateTimeStr(
                            alert.lastActivity,
                          );

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E1B4B).withOpacity(0.4)
                                  : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF3730A3)
                                    : const Color(0xFFFCA5A5),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        alert.customerName,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? SmartStoreColors.darkTextPrimary
                                              : SmartStoreColors
                                                    .lightTextPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        alert.customText ??
                                            _tr(
                                                  'notifications.overdue_alert',
                                                  '{0} mijozining {1} UZS qarzi 1 oydan oshib ketdi!',
                                                )
                                                .replaceFirst(
                                                  '{0}',
                                                  alert.customerName,
                                                )
                                                .replaceFirst(
                                                  '{1}',
                                                  formattedDebt,
                                                ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFEF4444),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Sana: $dateStr',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? SmartStoreColors.darkTextMuted
                                              : SmartStoreColors.lightTextMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _formatCurrencyNum(num amount) {
    final intVal = amount.round();
    final str = intVal.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }
    return '${intVal < 0 ? "-" : ""}${buffer.toString()} UZS';
  }

  static String _formatDateTimeStr(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = (dt.year % 100).toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    _accountStatusSubscription?.cancel();
    _customerStatusSubscription?.cancel();
    _authStateSubscription?.cancel();
    _sidebarController.dispose();
    ThemeController.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDarkMode;

    final sidebarBg = isDark ? SmartStoreColors.darkSurface : _lightSidebar;
    final topBarBg = isDark ? SmartStoreColors.darkSurface : _lightTopBar;
    final pageBg = isDark ? SmartStoreColors.darkBackground : _lightPageBg;
    final dividerColor = isDark ? SmartStoreColors.darkDivider : _lightHairline;

    return Scaffold(
      backgroundColor: pageBg,
      body: Stack(
        children: [
          Row(
            children: [
              // ── Sidebar ──
              AnimatedBuilder(
                animation: _sidebarAnimation,
                builder: (context, child) {
                  // Calculate current width based on animation value
                  final double currentWidth =
                      _sidebarExpandedWidth * _sidebarAnimation.value +
                      _sidebarCollapsedWidth * (1 - _sidebarAnimation.value);
                  // Whether tiles should render in "expanded" (row w/ label) mode.
                  // Switch as soon as we're past the halfway point of the animation
                  // instead of only at fully-expanded, so text doesn't get squeezed
                  // into a too-narrow Row and overflow mid-animation.

                  final bool renderExpanded = _sidebarAnimation.value > 0.5;

                  return ClipRect(
                    child: Container(
                      width: currentWidth,
                      decoration: BoxDecoration(
                        color: sidebarBg,
                        border: Border(
                          right: BorderSide(color: dividerColor, width: 1),
                        ),
                        boxShadow: isDark
                            ? []
                            : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 20,
                                  offset: const Offset(4, 0),
                                ),
                              ],
                      ),
                      child: Column(
                        children: [
                          // ── Sidebar Header ──
                          _SidebarHeader(
                            isDark: isDark,
                            dividerColor: dividerColor,
                            isExpanded: renderExpanded,
                          ),

                          // ── Navigation Items ──
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              children: [
                                if (renderExpanded)
                                  _SidebarGroup(
                                    label: 'nav.group_main'.tr(),
                                    isDark: isDark,
                                    dividerColor: dividerColor,
                                  ),
                                _SidebarTile(
                                  icon: Icons.dashboard_rounded,
                                  label: 'nav.home'.tr(context: context),
                                  active: _selectedSection == _Section.home,
                                  isDark: isDark,
                                  isExpanded: renderExpanded,
                                  onTap: () => navigateToSection(_Section.home),
                                ),
                                _SidebarTile(
                                  icon: Icons.sell_rounded,
                                  label: 'nav.selling'.tr(context: context),
                                  active: _selectedSection == _Section.selling,
                                  isDark: isDark,
                                  isExpanded: renderExpanded,
                                  onTap: () =>
                                      navigateToSection(_Section.selling),
                                ),
                                _SidebarTile(
                                  icon: Icons.add_box_rounded,
                                  label: 'nav.adding'.tr(context: context),
                                  active: _selectedSection == _Section.adding,
                                  isDark: isDark,
                                  isExpanded: renderExpanded,
                                  onTap: () =>
                                      navigateToSection(_Section.adding),
                                ),
                                _SidebarTile(
                                  icon: Icons.inventory_2_rounded,
                                  label: 'nav.stock'.tr(context: context),
                                  active: _selectedSection == _Section.stock,
                                  isDark: isDark,
                                  isExpanded: renderExpanded,
                                  onTap: () =>
                                      navigateToSection(_Section.stock),
                                ),
                                _SidebarTile(
                                  icon: Icons.people_rounded,
                                  label: 'nav.customers'.tr(context: context),
                                  active:
                                      _selectedSection == _Section.customers,
                                  isDark: isDark,
                                  isExpanded: renderExpanded,
                                  onTap: () =>
                                      navigateToSection(_Section.customers),
                                ),
                                _SidebarTile(
                                  icon: Icons.attach_money_rounded,
                                  label: 'nav.finance'.tr(),
                                  active: _selectedSection == _Section.finance,
                                  isDark: isDark,
                                  isExpanded: renderExpanded,
                                  onTap: () =>
                                      navigateToSection(_Section.finance),
                                ),
                                _SidebarTile(
                                  icon: Icons.analytics_rounded,
                                  label: 'nav.analytics'.tr(),
                                  active:
                                      _selectedSection == _Section.analytics,
                                  isDark: isDark,
                                  isExpanded: renderExpanded,
                                  onTap: () =>
                                      navigateToSection(_Section.analytics),
                                ),
                                const SizedBox(height: 8),
                                // ── Divider between Main and System groups ──
                                _SidebarDivider(
                                  isDark: isDark,
                                  dividerColor: dividerColor,
                                ),
                                const SizedBox(height: 8),
                                if (renderExpanded)
                                  _SidebarGroup(
                                    label: 'nav.group_system'.tr(),
                                    isDark: isDark,
                                    dividerColor: dividerColor,
                                  ),
                                _SidebarTile(
                                  icon: Icons.settings_rounded,
                                  label: 'nav.settings'.tr(),
                                  active: _selectedSection == _Section.settings,
                                  isDark: isDark,
                                  isExpanded: renderExpanded,
                                  onTap: () =>
                                      navigateToSection(_Section.settings),
                                ),
                              ],
                            ),
                          ),

                          // ── Sidebar Footer: Logout Button ──
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: dividerColor, width: 1),
                              ),
                            ),
                            child: _SidebarLogoutButton(
                              isDark: isDark,
                              isExpanded: renderExpanded,
                              onTap: logout,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // ── Main Content ──
              Expanded(
                child: Column(
                  children: [
                    // ── Top Bar ──
                    Container(
                      height: 80,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: topBarBg,
                        border: Border(
                          bottom: BorderSide(color: dividerColor, width: 1),
                        ),
                        boxShadow: isDark
                            ? []
                            : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Row(
                        children: [
                          // Sidebar Toggle
                          _TopBarIconButton(
                            icon: _isSidebarOpen
                                ? Icons.menu_open_rounded
                                : Icons.menu_rounded,
                            isDark: isDark,
                            onTap: toggleSidebar,
                            tooltip: _isSidebarOpen
                                ? 'topbar.close_sidebar'.tr(context: context)
                                : 'topbar.open_sidebar'.tr(context: context),
                          ),
                          const SizedBox(width: 14),

                          // Page Title
                          Text(
                            _getSectionTitle(context),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? SmartStoreColors.darkTextPrimary
                                  : SmartStoreColors.lightTextPrimary,
                              letterSpacing: 0.2,
                            ),
                          ),

                          const Spacer(),

                          // Support Center
                          _TopBarIconButton(
                            icon: Icons.help_outline_rounded,
                            isDark: isDark,
                            onTap: _showSupportCenterDialog,
                            tooltip: 'topbar.support'.tr(context: context),
                          ),
                          const SizedBox(width: 8),

                          // Notifications Button with Red Counter Badge
                          ListenableBuilder(
                            listenable: NotificationController.instance,
                            builder: (context, _) {
                              final count =
                                  NotificationController.instance.unreadCount;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  _TopBarIconButton(
                                    icon: Icons.notifications_none_rounded,
                                    isDark: isDark,
                                    onTap: _showNotificationsDialog,
                                    tooltip: 'topbar.notifications'.tr(
                                      context: context,
                                    ),
                                  ),
                                  if (count > 0)
                                    Positioned(
                                      right: -2,
                                      top: -2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0xFFEF4444,
                                              ).withOpacity(0.4),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 18,
                                          minHeight: 18,
                                        ),
                                        child: Text(
                                          '+$count',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(width: 8),

                          // Language Switcher
                          PopupMenuButton<String>(
                            icon: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? SmartStoreColors.darkSurfaceVariant
                                          .withOpacity(0.5)
                                    : SmartStoreColors.lightSurfaceVariant,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark
                                      ? SmartStoreColors.darkDivider
                                      : SmartStoreColors.lightDivider,
                                ),
                              ),
                              child: Icon(
                                Icons.language_rounded,
                                color: isDark
                                    ? SmartStoreColors.darkTextPrimary
                                    : SmartStoreColors.lightTextPrimary,
                                size: 19,
                              ),
                            ),
                            onSelected: (val) async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setString('language', val);
                              if (!context.mounted) return;
                              if (val == 'English') {
                                await context.setLocale(
                                  const Locale('en', 'US'),
                                );
                              } else if (val == 'Russian') {
                                await context.setLocale(
                                  const Locale('ru', 'RU'),
                                );
                              } else if (val == 'Uzbek') {
                                await context.setLocale(
                                  const Locale('uz', 'UZ'),
                                );
                              }
                              if (mounted) {
                                setState(() {});
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'English',
                                child: Text('English'),
                              ),
                              PopupMenuItem(
                                value: 'Russian',
                                child: Text('Русский'),
                              ),
                              PopupMenuItem(
                                value: 'Uzbek',
                                child: Text('Oʻzbekcha'),
                              ),
                            ],
                            tooltip: 'settings.language'.tr(context: context),
                            offset: const Offset(0, 45),
                            color: isDark
                                ? SmartStoreColors.darkSurface
                                : SmartStoreColors.lightSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Dark Mode Toggle
                          _TopBarIconButton(
                            icon: isDark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            isDark: isDark,
                            onTap: () => ThemeController.instance.toggle(),
                            tooltip: isDark
                                ? 'topbar.light_mode'.tr(context: context)
                                : 'topbar.dark_mode'.tr(context: context),
                          ),
                          const SizedBox(width: 8),

                          // ── Online Status Badge ──
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (_isOnline
                                          ? SmartStoreColors.success
                                          : SmartStoreColors.danger)
                                      .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    (_isOnline
                                            ? SmartStoreColors.success
                                            : SmartStoreColors.danger)
                                        .withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _isOnline
                                        ? SmartStoreColors.success
                                        : SmartStoreColors.danger,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  _isOnline
                                      ? 'topbar.online'.tr(context: context)
                                      : 'topbar.offline'.tr(context: context),
                                  style: TextStyle(
                                    color: _isOnline
                                        ? SmartStoreColors.success
                                        : SmartStoreColors.danger,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Page Content ──
                    Expanded(child: _buildPageContent()),
                  ],
                ),
              ),
            ],
          ),
          if (_isUserBlocked)
            Positioned.fill(
              child: _AccountBlockedOverlay(
                onReturnToLogin: _returnToLoginFromBlockedAccount,
              ),
            ),
        ],
      ),
    );
  }

  String _getSectionTitle(BuildContext context) {
    switch (_selectedSection) {
      case _Section.home:
        return 'titles.home'.tr(context: context);
      case _Section.selling:
        return 'titles.selling'.tr(context: context);
      case _Section.adding:
        return 'titles.adding'.tr(context: context);
      case _Section.stock:
        return 'titles.stock'.tr(context: context);
      case _Section.customers:
        return 'titles.customers'.tr(context: context);
      case _Section.finance:
        return 'titles.finance'.tr(context: context);
      case _Section.analytics:
        return 'titles.analytics'.tr(context: context);
      case _Section.settings:
        return 'titles.settings'.tr(context: context);
    }
  }

  Widget _buildPageContent() {
    switch (_selectedSection) {
      case _Section.home:
        return const HomePage();
      case _Section.selling:
        return const SellingPage();
      case _Section.adding:
        return const AddingPage();
      case _Section.stock:
        return const StockPage();
      case _Section.customers:
        return const CustomersPage();
      case _Section.finance:
        return const FinancePage();
      case _Section.analytics:
        return const AnalyticsPage();
      case _Section.settings:
        return const SettingsPage();
    }
  }
}

class _AccountBlockedOverlay extends StatelessWidget {
  const _AccountBlockedOverlay({required this.onReturnToLogin});

  final VoidCallback onReturnToLogin;

  Future<void> _openTelegram(BuildContext context) async {
    final uri = Uri.parse('https://t.me/+998501551809');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Telegram ochilmadi.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.94),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: SmartStoreColors.danger.withOpacity(0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: SmartStoreColors.danger.withOpacity(0.45),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 62,
                      color: SmartStoreColors.danger,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Siz to\'lovni vaqtida to\'lamaganligiz sababli, admin tomonidan bloklangansiz.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Blokdan ochilish uchun, admin bilan bog\'laning...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 17,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  InkWell(
                    onTap: () => _openTelegram(context),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF229ED9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.send_rounded, color: Colors.white),
                          SizedBox(width: 10),
                          Text(
                            'Telegram | +998501551809',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: onReturnToLogin,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Login sahifasiga qaytish'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sidebar Header Widget ──
class _SidebarHeader extends StatelessWidget {
  final bool isDark;
  final Color dividerColor;
  final bool isExpanded;

  const _SidebarHeader({
    required this.isDark,
    required this.dividerColor,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context) {
    // Windows text scaling can make the two-line brand label taller than the
    // fixed header. Give it proportional space whenever the sidebar is open.
    final double textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final double extraHeight = ((textScale - 1.0).clamp(0.0, 1.0) * 24.0)
        .toDouble();
    final double headerHeight = isExpanded ? 80.0 + extraHeight : 80.0;

    return Container(
      height: headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: isExpanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          const _SidebarLogoButton(),
          if (isExpanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                        children: [
                          TextSpan(
                            text: 'Smart',
                            style: TextStyle(color: Color(0xFF0EA5E9)),
                          ),
                          TextSpan(
                            text: 'Store',
                            style: TextStyle(color: Color(0xFF22C55E)),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'POS System',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? SmartStoreColors.darkTextMuted
                            : SmartStoreColors.lightTextMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SidebarLogoButton extends StatelessWidget {
  const _SidebarLogoButton();

  void _showLogoPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 30,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Image.asset('assets/logo.png', fit: BoxFit.contain),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showLogoPreview(context),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [SmartStoreColors.primary, SmartStoreColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: SmartStoreColors.primary.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/logo.png',
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sidebar Group Label ──
class _SidebarGroup extends StatelessWidget {
  final String label;
  final bool isDark;
  final Color dividerColor;

  const _SidebarGroup({
    required this.label,
    required this.isDark,
    required this.dividerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: isDark
              ? SmartStoreColors.darkTextMuted
              : SmartStoreColors.lightTextMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ── Sidebar Divider Widget ──
class _SidebarDivider extends StatelessWidget {
  final bool isDark;
  final Color dividerColor;

  const _SidebarDivider({required this.isDark, required this.dividerColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              dividerColor,
              dividerColor,
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sidebar Logout Button Widget ──
class _SidebarLogoutButton extends StatelessWidget {
  final bool isDark;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SidebarLogoutButton({
    required this.isDark,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Log Out',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: isExpanded ? 14 : 0),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFFEF4444).withOpacity(0.12),
                        const Color(0xFFDC2626).withOpacity(0.08),
                      ]
                    : [
                        const Color(0xFFEF4444).withOpacity(0.08),
                        const Color(0xFFDC2626).withOpacity(0.05),
                      ],
              ),
              border: Border.all(
                color: const Color(0xFFEF4444).withOpacity(0.25),
                width: 1,
              ),
            ),
            child: isExpanded
                ? Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          color: Color(0xFFEF4444),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Log Out',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEF4444),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: const Color(0xFFEF4444).withOpacity(0.6),
                      ),
                    ],
                  )
                : const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFEF4444),
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Sidebar Tile Widget ──
class _SidebarTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool isDark;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.isDark,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
  }

  void _triggerSpin() {
    if (_rotationController.isAnimating) {
      _rotationController.stop();
    }
    _rotationController
        .animateTo(
          1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOutCubic,
        )
        .then((_) {
          if (!mounted) return;
          _rotationController.animateBack(
            0.0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
          );
        });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.active
        ? Colors.white
        : widget.isDark
        ? SmartStoreColors.darkTextSecondary
        : SmartStoreColors.lightTextSecondary;

    final iconColor = widget.active
        ? Colors.white
        : widget.isDark
        ? SmartStoreColors.darkTextMuted
        : SmartStoreColors.lightTextMuted;

    final iconWidget = AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        final angle = _rotationController.value * math.pi;
        return Transform.rotate(
          angle: angle,
          child: Icon(widget.icon, color: iconColor, size: 24),
        );
      },
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: widget.active ? null : Colors.transparent,
        gradient: widget.active
            ? const LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [Colors.lightBlue, Colors.lightGreen],
              )
            : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: MouseRegion(
          onEnter: (_) => _triggerSpin(),
          child: InkWell(
            onTap: () {
              _triggerSpin();
              widget.onTap();
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 48,
              padding: EdgeInsets.symmetric(
                horizontal: widget.isExpanded ? 14 : 0,
              ),
              alignment: Alignment.center,
              child: widget.isExpanded
                  ? Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        AnimatedBuilder(
                          animation: _rotationController,
                          builder: (context, child) {
                            final angle = _rotationController.value * math.pi;
                            return Transform.rotate(
                              angle: angle,
                              child: Icon(
                                widget.icon,
                                color: iconColor,
                                size: 24,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            widget.label,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: widget.active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: textColor,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (widget.active)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    )
                  : iconWidget,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Top Bar Icon Button Widget ──
class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  final String tooltip;

  const _TopBarIconButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDark
                  ? SmartStoreColors.darkSurfaceVariant.withOpacity(0.5)
                  : SmartStoreColors.lightSurfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? SmartStoreColors.darkDivider
                    : SmartStoreColors.lightDivider,
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: isDark
                  ? SmartStoreColors.darkTextPrimary
                  : SmartStoreColors.lightTextPrimary,
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Offline Reminder Dialog ──
class _OfflineReminderDialog extends StatelessWidget {
  final VoidCallback onRetry;
  const _OfflineReminderDialog({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDarkMode;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: isDark
              ? SmartStoreColors.darkSurface
              : SmartStoreColors.lightSurface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: SmartStoreColors.danger.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: SmartStoreColors.danger.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: SmartStoreColors.danger.withOpacity(0.4),
                ),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: SmartStoreColors.danger,
                size: 30,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'offline_dialog.title'.tr(),
              style: TextStyle(
                color: isDark
                    ? SmartStoreColors.darkTextPrimary
                    : SmartStoreColors.lightTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'offline_dialog.subtitle'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? SmartStoreColors.darkTextMuted
                    : SmartStoreColors.lightTextMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SmartStoreColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                label: Text(
                  'offline_dialog.retry'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// Support Contact Tile Widget
// ───────────────────────────────────────────────────────────────
class _SupportContactTile extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String value;
  final String subtitle;
  final VoidCallback onTap;

  const _SupportContactTile({
    required this.isDark,
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? SmartStoreColors.darkSurfaceVariant.withOpacity(0.4)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? SmartStoreColors.darkDivider
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: iconGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: iconGradient.first.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? SmartStoreColors.darkTextMuted
                                : SmartStoreColors.lightTextMuted,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF0284C7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? SmartStoreColors.darkTextPrimary
                            : SmartStoreColors.lightTextPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: isDark
                    ? SmartStoreColors.darkTextSecondary
                    : SmartStoreColors.lightTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

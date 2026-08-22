import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_store/screens/theme_controller.dart';
import '../screens/layout_page.dart';

class PinLockPage extends StatefulWidget {
  const PinLockPage({super.key});

  @override
  State<PinLockPage> createState() => _PinLockPageState();
}

class _PinLockPageState extends State<PinLockPage> {
  final FocusNode _focusNode = FocusNode();
  List<int> _pinDigits = List.filled(6, -1);
  int _currentIndex = 0;
  String _errorMessage = '';
  bool _isLoading = false;
  String _correctPin = '';

  @override
  void initState() {
    super.initState();
    _loadPin();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    ThemeController.instance.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.dispose();
    ThemeController.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _loadPin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _correctPin = prefs.getString('app_pin') ?? '';
      });
    } catch (e) {
      debugPrint('Error loading pin: $e');
    }
  }

  void _onDigitPressed(int digit) {
    if (_currentIndex >= 6 || _isLoading) return;

    setState(() {
      _pinDigits[_currentIndex] = digit;
      _currentIndex++;
      _errorMessage = '';
    });

    if (_currentIndex == 6) {
      _verifyPin();
    }
  }

  void _onBackspacePressed() {
    if (_currentIndex == 0) return;
    setState(() {
      _currentIndex--;
      _pinDigits[_currentIndex] = -1;
      _errorMessage = '';
    });
  }

  Future<void> _verifyPin() async {
    setState(() => _isLoading = true);

    final enteredPin = _pinDigits.join('');

    await Future.delayed(const Duration(milliseconds: 500));

    if (enteredPin == _correctPin) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const LayoutPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 450),
          ),
        );
      }
    } else {
      setState(() {
        _errorMessage = 'Incorrect PIN. Please try again.';
        _pinDigits = List.filled(6, -1);
        _currentIndex = 0;
        _isLoading = false;
      });
    }
  }

  void _onClearPressed() {
    setState(() {
      _pinDigits = List.filled(6, -1);
      _currentIndex = 0;
      _errorMessage = '';
    });
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    if (_isLoading) return;

    if (event.logicalKey == LogicalKeyboardKey.digit0 ||
        event.logicalKey == LogicalKeyboardKey.numpad0) {
      _onDigitPressed(0);
    } else if (event.logicalKey == LogicalKeyboardKey.digit1 ||
        event.logicalKey == LogicalKeyboardKey.numpad1) {
      _onDigitPressed(1);
    } else if (event.logicalKey == LogicalKeyboardKey.digit2 ||
        event.logicalKey == LogicalKeyboardKey.numpad2) {
      _onDigitPressed(2);
    } else if (event.logicalKey == LogicalKeyboardKey.digit3 ||
        event.logicalKey == LogicalKeyboardKey.numpad3) {
      _onDigitPressed(3);
    } else if (event.logicalKey == LogicalKeyboardKey.digit4 ||
        event.logicalKey == LogicalKeyboardKey.numpad4) {
      _onDigitPressed(4);
    } else if (event.logicalKey == LogicalKeyboardKey.digit5 ||
        event.logicalKey == LogicalKeyboardKey.numpad5) {
      _onDigitPressed(5);
    } else if (event.logicalKey == LogicalKeyboardKey.digit6 ||
        event.logicalKey == LogicalKeyboardKey.numpad6) {
      _onDigitPressed(6);
    } else if (event.logicalKey == LogicalKeyboardKey.digit7 ||
        event.logicalKey == LogicalKeyboardKey.numpad7) {
      _onDigitPressed(7);
    } else if (event.logicalKey == LogicalKeyboardKey.digit8 ||
        event.logicalKey == LogicalKeyboardKey.numpad8) {
      _onDigitPressed(8);
    } else if (event.logicalKey == LogicalKeyboardKey.digit9 ||
        event.logicalKey == LogicalKeyboardKey.numpad9) {
      _onDigitPressed(9);
    } else if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      _onBackspacePressed();
    } else if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.keyC) {
      _onClearPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDarkMode;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      body: RawKeyboardListener(
        focusNode: _focusNode,
        onKey: _handleKeyEvent,
        child: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withOpacity(0.3),
                          blurRadius: 30,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset('assets/logo.png', fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'SmartStore',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter PIN to continue',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (index) {
                      final bool isFilled = _pinDigits[index] != -1;
                      final bool isActive = index == _currentIndex && !isFilled;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFilled
                              ? const Color(0xFF2563EB)
                              : Colors.transparent,
                          border: Border.all(
                            color: isFilled || isActive
                                ? const Color(0xFF2563EB)
                                : (isDark
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade300),
                            width: isActive ? 2.5 : 1.5,
                          ),
                          boxShadow: isFilled
                              ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF2563EB,
                                    ).withOpacity(0.4),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                      );
                    }),
                  ),
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.red.shade900.withOpacity(0.3)
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.red.shade700
                              : Colors.red.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: isDark
                                ? Colors.red.shade400
                                : Colors.red.shade600,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _errorMessage,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.red.shade400
                                  : Colors.red.shade600,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                            3,
                            (i) => _buildNumberButton(i + 1, isDark),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                            3,
                            (i) => _buildNumberButton(i + 4, isDark),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildNumberButton(7, isDark),
                            _buildNumberButton(8, isDark),
                            _buildNumberButton(9, isDark),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildClearButton(isDark),
                            _buildNumberButton(0, isDark),
                            _buildBackspaceButton(isDark),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_isLoading) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF2563EB),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade800.withOpacity(0.3)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '⌨️ Backspace: delete • ESC/C: clear',
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                        fontSize: 11,
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

  Widget _buildNumberButton(int digit, bool isDark) {
    return GestureDetector(
      onTap: () {
        if (!_isLoading) {
          HapticFeedback.lightImpact();
          _onDigitPressed(digit);
          _focusNode.requestFocus();
        }
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '$digit',
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton(bool isDark) {
    return GestureDetector(
      onTap: () {
        if (!_isLoading) {
          HapticFeedback.lightImpact();
          _onBackspacePressed();
          _focusNode.requestFocus();
        }
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? Colors.grey.shade700.withOpacity(0.3)
                : Colors.grey.shade300.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.backspace_rounded,
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildClearButton(bool isDark) {
    return GestureDetector(
      onTap: () {
        if (!_isLoading) {
          HapticFeedback.lightImpact();
          _onClearPressed();
          _focusNode.requestFocus();
        }
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? Colors.grey.shade700.withOpacity(0.3)
                : Colors.grey.shade300.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.clear_rounded,
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
          size: 26,
        ),
      ),
    );
  }
}

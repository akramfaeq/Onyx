import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF0F0F1A);
  static const Color surface    = Color(0xFF1E1E2E);
  static const Color primary    = Color(0xFF7C6AF7);
  static const Color primaryLight = Color(0xFFA78BFA);
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF888888);
  static const Color success    = Color(0xFF4ADE80);

  static ThemeData get darkTheme => ThemeData(
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      surface: surface,
    ),
    fontFamily: 'SF Pro Display',
    useMaterial3: true,
  );
}
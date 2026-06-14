// lib/core/theme.dart — Final
import 'package:flutter/material.dart';

class AppTheme {
  static const Color bgColor = Color(0xFF0A0A14);
  static const Color primaryColor = Color(0xFF6C63FF);
  static const Color accentColor = Color(0xFF00D4AA);
  static const Color cardColor = Color(0xFF1A1A2E);
  static const Color surfaceColor = Color(0xFF12121F);

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgColor,
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: accentColor,
      surface: cardColor,
      background: bgColor,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bgColor,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
    ),
    tabBarTheme: const TabBarTheme(
      labelColor: primaryColor,
      unselectedLabelColor: Colors.white38,
      indicatorColor: primaryColor,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primaryColor),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: primaryColor),
      ),
      hintStyle: const TextStyle(color: Colors.white38),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: cardColor,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    fontFamily: 'Inter',
  );
}

// ─── lib/core/constants.dart — Final ──────────────────────
class AppConstants {
  // Worker URL — deploy করার পর এখানে বসাও
  static const String workerBaseUrl =
      'https://atlaspro-db.hamza818483.workers.dev';

  static const String appName = 'AtlasPro';
  static const String appVersion = '1.0.0';
  static const String adminPhone = '01754365403';

  // Limits
  static const int defaultFreePageLimit = 5;
  static const int defaultPremiumPageLimit = 100;
  static const int maxExamPages = 5;
  static const int maxBreaks = 3;
  static const int maxBreakSeconds = 3600;
  static const int mcqExamSize = 10;

  // Supabase (backup)
  static const String supabaseUrl = 'https://cctbwbipsoapskajoubr.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNjdGJ3Ymlwc29hcHNrYWpvdWJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEzNjQ0MTcsImV4cCI6MjA5Njk0MDQxN30.JhBlyfKtIdIsBGAXt4j32ctj7Sr_XsCcdB7xaxs_6CY';
}

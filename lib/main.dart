import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

// ============================================================
// FIREBASE INITIALIZATION
// ============================================================

  await Firebase.initializeApp();

// ============================================================
// SUPABASE INITIALIZATION
// ============================================================
//
// Replace these two values with the credentials from your
// Supabase project.
//
// Supabase Dashboard:
// Project -> Connect / API
//
// Use the client-side Publishable Key (or legacy anon key),
// NOT the service_role/secret key.
// ============================================================

  const String supabaseUrl = 'https://dwfoakrsoqiqpbjbonjq.supabase.co';

  const String supabasePublishableKey =
      'sb_publishable_HyPhbNAAflzg9e-Woe1wmw_kqehGfin';

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

// ============================================================
// START APPLICATION
// ============================================================

  runApp(const SurgiAssistApp());
}

// ============================================================
// GLOBAL SUPABASE CLIENT
// ============================================================
//
// You can use this anywhere in your application:
//
// supabase.from('table_name').select();
//
// supabase.storage.from('bucket_name').upload(...);
//
// ============================================================

final SupabaseClient supabase = Supabase.instance.client;

class SurgiAssistApp extends StatelessWidget {
  const SurgiAssistApp({super.key});

// ============================================================
// SURGIASSIST COLOR PALETTE
// ============================================================

  static const Color deepNavy = Color(0xFF0B1F33);
  static const Color navyBlue = Color(0xFF123A56);
  static const Color surgicalTeal = Color(0xFF0E7490);
  static const Color medicalCyan = Color(0xFF22D3EE);

  static const Color softBackground = Color(0xFFF5F8FA);
  static const Color white = Color(0xFFFFFFFF);

  static const Color deepSlate = Color(0xFF172B3A);
  static const Color slate = Color(0xFF64748B);

  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color critical = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SurgiAssist',

      debugShowCheckedModeBanner: false,

// ========================================================
// APPLICATION THEME
// ========================================================

      theme: ThemeData(
        useMaterial3: true,

        scaffoldBackgroundColor: softBackground,

        colorScheme: const ColorScheme(
          brightness: Brightness.light,

          primary: deepNavy,
          onPrimary: white,

          primaryContainer: navyBlue,
          onPrimaryContainer: white,

          secondary: surgicalTeal,
          onSecondary: white,

          secondaryContainer: Color(0xFFDDF6FA),
          onSecondaryContainer: deepNavy,

          tertiary: medicalCyan,
          onTertiary: deepNavy,

          error: critical,
          onError: white,

          surface: white,
          onSurface: deepSlate,

          surfaceContainerHighest: Color(0xFFE8EEF2),
        ),

// ======================================================
// TYPOGRAPHY
// ======================================================

        textTheme: GoogleFonts.poppinsTextTheme(),

// ======================================================
// APP BAR
// ======================================================

        appBarTheme: const AppBarTheme(
          backgroundColor: white,
          foregroundColor: deepNavy,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),

// ======================================================
// CARDS
// ======================================================

        cardTheme: const CardThemeData(
          color: white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
        ),

// ======================================================
// INPUT FIELDS
// ======================================================

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: white,

          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFD9E2E8),
            ),
          ),

          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFD9E2E8),
            ),
          ),

          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: surgicalTeal,
              width: 1.5,
            ),
          ),

          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: critical,
            ),
          ),

          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),

// ======================================================
// ELEVATED BUTTONS
// ======================================================

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: deepNavy,
            foregroundColor: white,

            elevation: 0,

            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 15,
            ),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),

            textStyle: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),

// ======================================================
// OUTLINED BUTTONS
// ======================================================

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: deepNavy,

            side: const BorderSide(
              color: surgicalTeal,
              width: 1.2,
            ),

            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 15,
            ),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

// ======================================================
// DIVIDERS
// ======================================================

        dividerTheme: const DividerThemeData(
          color: Color(0xFFE2E8ED),
          thickness: 1,
        ),
      ),

// ========================================================
// INITIAL SCREEN
// ========================================================

      home: const SplashScreen(),
    );
  }
}

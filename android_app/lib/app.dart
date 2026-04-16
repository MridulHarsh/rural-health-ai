import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/translations.dart';
import 'screens/home_screen.dart';
import 'screens/assessment_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'services/ml_service.dart';

class RuralHealthApp extends StatefulWidget {
  const RuralHealthApp({super.key});

  static void setLocale(BuildContext context, Locale locale) {
    final state = context.findAncestorStateOfType<_RuralHealthAppState>();
    state?.setLocale(locale);
  }

  @override
  State<RuralHealthApp> createState() => _RuralHealthAppState();
}

class _RuralHealthAppState extends State<RuralHealthApp> {
  Locale _locale = const Locale('en');
  final MLService _mlService = MLService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('language') ?? 'en';
    if (!mounted) return;
    setState(() => _locale = Locale(langCode));

    // Pre-load ML model
    try {
      await _mlService.initialize();
    } catch (e) {
      debugPrint('ML model loading deferred: $e');
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  void setLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', locale.languageCode);
    if (!mounted) return;
    setState(() => _locale = locale);
  }

  @override
  void dispose() {
    _mlService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Color Palette: Warm, trustworthy healthcare theme ──
    const Color primaryGreen = Color(0xFF1B8A6B);
    const Color accentTeal = Color(0xFF14B8A6);
    const Color warmWhite = Color(0xFFFAF9F6);
    const Color deepSlate = Color(0xFF1E293B);
    const Color softGray = Color(0xFFF1F5F9);
    const Color errorRed = Color(0xFFDC2626);

    return MaterialApp(
      title: 'Rural Health AI',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: AppTranslations.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: warmWhite,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryGreen,
          brightness: Brightness.light,
          primary: primaryGreen,
          secondary: accentTeal,
          error: errorRed,
          surface: warmWhite,
          onSurface: deepSlate,
        ),
        textTheme: GoogleFonts.poppinsTextTheme().copyWith(
          headlineLarge: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: deepSlate,
          ),
          headlineMedium: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: deepSlate,
          ),
          titleLarge: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: deepSlate,
          ),
          bodyLarge: GoogleFonts.poppins(
            fontSize: 16,
            color: deepSlate,
          ),
          bodyMedium: GoogleFonts.poppins(
            fontSize: 14,
            color: deepSlate.withValues(alpha: 0.8),
          ),
          labelLarge: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: warmWhite,
          foregroundColor: deepSlate,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: deepSlate,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: softGray,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryGreen, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
      home: _isLoading ? _buildSplash() : HomeScreen(mlService: _mlService),
      routes: {
        '/assessment': (context) => AssessmentScreen(mlService: _mlService),
        '/history': (context) => const HistoryScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }

  Widget _buildSplash() {
    return const Scaffold(
      backgroundColor: Color(0xFF1B8A6B),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.health_and_safety, size: 80, color: Colors.white),
            SizedBox(height: 24),
            Text(
              'Rural Health AI',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

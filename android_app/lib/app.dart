import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/translations.dart';
import 'screens/home_screen.dart';
import 'screens/assessment_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/mch_screen.dart';
import 'screens/dosage_screen.dart';
import 'dart:async';

import 'screens/households_list_screen.dart';
import 'screens/outbox_screen.dart';
import 'services/connectivity_service.dart';
import 'services/encryption_service.dart';
import 'services/handoff_queue_service.dart';
import 'services/ml_service.dart';
import 'services/notification_service.dart';

/// Global navigator key — lets [NotificationService]'s tap handler push
/// the `/outbox` route without needing a BuildContext from inside the
/// background isolate that delivers the tap.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
  StreamSubscription<bool>? _connSub;

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

    // Initialize at-rest encryption for PII. Cheap and synchronous-enough.
    try {
      await EncryptionService.initialize();
    } catch (e) {
      debugPrint('EncryptionService init failed (PII will be plaintext): $e');
    }

    // Start transport listener so the Outbox can make offline/online
    // decisions without each screen polling separately.
    try {
      await ConnectivityService.start();
    } catch (e) {
      debugPrint('ConnectivityService start failed: $e');
    }

    // Wire local notifications: on offline→online transitions, tell the
    // ASHA that queued messages are ready to send. Permission prompt is
    // only shown on Android 13+.
    try {
      await NotificationService.initialize(onOpenOutbox: _openOutbox);
      await NotificationService.requestPermission();
      _connSub = ConnectivityService.onChange.listen(_onConnectivityChange);
    } catch (e) {
      debugPrint('NotificationService init failed: $e');
    }

    // Pre-load ML model
    try {
      await _mlService.initialize();
    } catch (e) {
      debugPrint('ML model loading deferred: $e');
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  /// Fired from [ConnectivityService]. [online] is the new state. We only
  /// act on offline→online transitions (the stream already de-duplicates).
  Future<void> _onConnectivityChange(bool online) async {
    if (!online) return;
    try {
      final pending = await HandoffQueueService.pendingCount();
      if (pending <= 0) return;
      await NotificationService.showOutboxPending(
        pendingCount: pending,
        title: AppTranslations.t(
            'notif_outbox_ready_title', _locale.languageCode),
        body: AppTranslations.t(
            'notif_outbox_ready_body', _locale.languageCode),
      );
    } catch (e) {
      debugPrint(
          '[App] outbox-pending notification error: ${e.runtimeType}');
    }
  }

  /// Tap-from-notification handler. Uses [navigatorKey] because the plugin
  /// delivers taps outside the widget tree (on cold start it can fire
  /// before `build` runs).
  void _openOutbox() {
    navigatorKey.currentState?.pushNamed('/outbox');
  }

  void setLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', locale.languageCode);
    if (!mounted) return;
    setState(() => _locale = locale);
  }

  @override
  void dispose() {
    _connSub?.cancel();
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
      navigatorKey: navigatorKey,
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
        '/inventory': (context) => const InventoryScreen(),
        '/mch': (context) => const MchScreen(),
        '/dosage': (context) => const DosageScreen(),
        '/outbox': (context) => const OutboxScreen(),
        '/households': (context) => const HouseholdsListScreen(),
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

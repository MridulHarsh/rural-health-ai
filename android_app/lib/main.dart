import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app is advertised as "fully offline after install"; allowing runtime
  // font fetching breaks that promise — a first launch in an area with no
  // signal would silently fall back to the system font and the UI would
  // look different from the APK QA'd in the office. If a typography mismatch
  // appears on-device, bundle the needed .ttf files under assets/fonts/ and
  // register them in pubspec.yaml rather than flipping this back to true.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Lock to portrait for consistent UX on low-end phones
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(const RuralHealthApp());
}

// ocr_service.dart
// Prescription/medical-report OCR via Google ML Kit — runs fully offline.
// Lets an ASHA worker photograph an old prescription and pull the text in,
// instead of retyping it. Borrowed from AASHA / Medigram / Karam Saathi decks.

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  final String rawText;
  final List<String> lines;
  OcrResult({required this.rawText, required this.lines});

  bool get isEmpty => rawText.trim().isEmpty;
}

class OcrService {
  static final _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// Extract text from an image file (path).
  static Future<OcrResult> extractFromFile(String imagePath) async {
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(input);
      final lines = <String>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          if (t.isNotEmpty) lines.add(t);
        }
      }
      return OcrResult(rawText: recognizedText.text, lines: lines);
    } catch (e) {
      debugPrint('[OcrService] extract error: $e');
      return OcrResult(rawText: '', lines: []);
    }
  }

  /// Try to pull medicine-looking lines out of raw OCR output. Heuristic:
  /// line mentions "mg"/"ml" OR matches the generic-medicine pattern
  /// "Capitalized word + number + unit". ASHA workers can still edit.
  static List<String> extractMedicineLines(OcrResult r) {
    final regex = RegExp(
      r'([A-Z][a-zA-Z\-]{2,})\s*(\d+)\s*(mg|ml|mcg|g|iu)',
      caseSensitive: false,
    );
    final hits = <String>[];
    for (final line in r.lines) {
      if (regex.hasMatch(line)) hits.add(line);
    }
    return hits;
  }

  /// Clean up - must be called when service is no longer needed.
  static void dispose() {
    _textRecognizer.close();
  }
}

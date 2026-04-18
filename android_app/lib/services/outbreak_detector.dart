// outbreak_detector.dart
// Village-level outbreak detector: scans saved assessments in the last N days,
// clusters by overlapping symptom profile + disease, and flags potential
// silent epidemics. Mirrors SwarmDoc / SwasthyaSathi / Karam Saathi decks.

import 'database_service.dart';

class OutbreakAlert {
  final String diseaseOrSymptom;
  final int caseCount;
  final int windowDays;
  final List<String> recentPatientNames;

  OutbreakAlert({
    required this.diseaseOrSymptom,
    required this.caseCount,
    required this.windowDays,
    required this.recentPatientNames,
  });

  bool get isSevere => caseCount >= 5;
}

class OutbreakDetector {
  /// Minimum overlapping cases in [windowDays] to flag a cluster.
  static const int _minCluster = 3;
  static const int _windowDays = 7;

  /// Run cluster analysis across saved assessments. Returns any alerts
  /// worth surfacing on the home screen.
  static Future<List<OutbreakAlert>> detect() async {
    final records = await DatabaseService.getAssessments();
    if (records.isEmpty) return [];

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: _windowDays));

    // Group by TOP condition name
    final byCondition = <String, List<Map<String, dynamic>>>{};
    // Also cluster by shared symptom signatures for unknown outbreaks
    final bySymptom = <String, List<Map<String, dynamic>>>{};

    for (final r in records) {
      final createdRaw = r['createdAt'] as String?;
      if (createdRaw == null) continue;
      final created = DateTime.tryParse(createdRaw);
      if (created == null || created.isBefore(cutoff)) continue;

      final conditions = r['conditions'];
      if (conditions is List && conditions.isNotEmpty) {
        final top = conditions.first;
        if (top is Map && top['name'] is String) {
          byCondition.putIfAbsent(top['name'] as String, () => []).add(r);
        }
      }

      final symptoms = r['symptoms'];
      if (symptoms is List) {
        for (final s in symptoms) {
          if (s is String) {
            bySymptom.putIfAbsent(s, () => []).add(r);
          }
        }
      }
    }

    final alerts = <OutbreakAlert>[];
    // Condition clusters are the strongest signal (same top diagnosis).
    byCondition.forEach((name, rs) {
      if (rs.length >= _minCluster) {
        alerts.add(OutbreakAlert(
          diseaseOrSymptom: name,
          caseCount: rs.length,
          windowDays: _windowDays,
          recentPatientNames: rs
              .map((r) => (r['patientName'] ?? 'Unknown').toString())
              .take(5)
              .toList(),
        ));
      }
    });

    // Also flag high-signal infectious symptoms clustering (fever + diarrhea,
    // etc.) even when top-condition varies. Tuned for rural outbreak signals.
    const watchSymptoms = {
      'bloody_diarrhea',
      'jaundice',
      'rash',
      'worms_in_stool',
      'severe_headache',
      'stiff_neck_with_fever',
      'whooping_sound',
    };
    bySymptom.forEach((sym, rs) {
      if (rs.length >= _minCluster && watchSymptoms.contains(sym)) {
        final alreadyFlagged = alerts.any((a) =>
            a.diseaseOrSymptom.toLowerCase().contains(sym.split('_').first));
        if (alreadyFlagged) return;
        alerts.add(OutbreakAlert(
          diseaseOrSymptom: sym.replaceAll('_', ' '),
          caseCount: rs.length,
          windowDays: _windowDays,
          recentPatientNames: rs
              .map((r) => (r['patientName'] ?? 'Unknown').toString())
              .take(5)
              .toList(),
        ));
      }
    });

    // Sort by severity (case count) descending
    alerts.sort((a, b) => b.caseCount.compareTo(a.caseCount));
    return alerts;
  }
}

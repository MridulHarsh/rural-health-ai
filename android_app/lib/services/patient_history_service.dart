// patient_history_service.dart
// Pivots the flat `assessments` history by patient identity so the ASHA can
// see longitudinal trajectories (same person across multiple visits) rather
// than just a date-sorted list. Groups by ABHA ID when present, with a
// name+age+gender fallback for patients who don't have one yet.
//
// Feature #6 in the NeuCure roadmap.

import '../models/patient_identity.dart';
import 'database_service.dart';

/// Per-patient rollup — what the patient-timeline screen renders.
class PatientTimeline {
  final PatientIdentity identity;
  final List<Map<String, dynamic>> visits; // raw decrypted assessment rows
  final List<VitalsPoint> vitalsSeries;

  const PatientTimeline({
    required this.identity,
    required this.visits,
    required this.vitalsSeries,
  });

  int get visitCount => visits.length;
  DateTime? get lastVisit =>
      visits.isEmpty ? null : visits.first['createdAt'] != null
          ? DateTime.tryParse(visits.first['createdAt'].toString())
          : null;
  String? get latestRisk =>
      visits.isEmpty ? null : visits.first['overallRisk']?.toString();
}

/// One timestamped set of vitals for charting. Missing fields are null —
/// the chart skips gaps rather than interpolating, which would be a
/// clinically misleading default.
class VitalsPoint {
  final DateTime at;
  final double? temperature; // °F
  final double? systolic;
  final double? diastolic;
  final double? heartRate;
  final double? spo2;
  final double? weight; // kg

  const VitalsPoint({
    required this.at,
    this.temperature,
    this.systolic,
    this.diastolic,
    this.heartRate,
    this.spo2,
    this.weight,
  });
}

class PatientHistoryService {
  /// Group all saved assessments by patient identity. Visits within each
  /// group are sorted newest-first. Returned in a UI-friendly order:
  /// patient with the most recent visit first.
  static Future<List<PatientTimeline>> listTimelines() async {
    final rows = await DatabaseService.getAssessments();
    final buckets = <String, List<Map<String, dynamic>>>{};
    final keyToIdentity = <String, PatientIdentity>{};
    for (final r in rows) {
      final ident = _identityFor(r);
      buckets.putIfAbsent(ident.key, () => []).add(r);
      // Overwrite with the latest row's identity display — keeps the most
      // recent name spelling / age on the timeline header (people's age
      // changes between visits, and the name capitalization might too).
      final existing = keyToIdentity[ident.key];
      if (existing == null || _isNewer(r, buckets[ident.key]!)) {
        keyToIdentity[ident.key] = ident;
      }
    }
    final timelines = <PatientTimeline>[];
    for (final entry in buckets.entries) {
      final visits = [...entry.value]..sort((a, b) {
          final da = DateTime.tryParse(a['createdAt']?.toString() ?? '');
          final db = DateTime.tryParse(b['createdAt']?.toString() ?? '');
          final ma = da?.millisecondsSinceEpoch ?? 0;
          final mb = db?.millisecondsSinceEpoch ?? 0;
          return mb.compareTo(ma);
        });
      timelines.add(PatientTimeline(
        identity: keyToIdentity[entry.key]!,
        visits: visits,
        vitalsSeries: _vitalsSeries(visits),
      ));
    }
    timelines.sort((a, b) {
      final ta = a.lastVisit?.millisecondsSinceEpoch ?? 0;
      final tb = b.lastVisit?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });
    return timelines;
  }

  /// Timeline for one specific identity. Convenience for screens that
  /// navigate in from a single history row.
  static Future<PatientTimeline?> timelineFor(PatientIdentity identity) async {
    final all = await listTimelines();
    for (final t in all) {
      if (t.identity == identity) return t;
    }
    return null;
  }

  /// Build the identity key for one raw row. Static because the history
  /// screen also calls this directly when jumping from a single row to
  /// the full timeline.
  static PatientIdentity identityForRow(Map<String, dynamic> r) =>
      _identityFor(r);

  // ────────────────────────────────────────────────────────────

  static PatientIdentity _identityFor(Map<String, dynamic> r) {
    final abha = (r['abhaId'] as String?)?.trim();
    final name = (r['patientName'] as String?)?.trim() ?? '';
    final age = (r['patientAge'] as int?) ?? 0;
    final gender = (r['patientGender'] as String?)?.trim() ?? '';
    if (abha != null && abha.isNotEmpty) {
      return PatientIdentity(
        source: 'abha',
        key: 'abha:$abha',
        displayName: name.isEmpty ? 'Unknown' : name,
        latestAge: age,
        gender: gender,
        abhaId: abha,
      );
    }
    final normName = name.toLowerCase();
    // Age bucket ±1 so a 41-year-old visiting at 40 and then 41 stays one
    // person. We bucket on the stored age (no birthday arithmetic) since
    // rural patients routinely report integer ages without a DOB.
    final bucket = age ~/ 2; // pairs (0-1, 2-3, ...). Conservative merge.
    final normGender = gender.toLowerCase();
    return PatientIdentity(
      source: 'approx',
      key: 'np:$normName|$bucket|$normGender',
      displayName: name.isEmpty ? 'Unknown' : name,
      latestAge: age,
      gender: gender,
    );
  }

  static bool _isNewer(
      Map<String, dynamic> candidate, List<Map<String, dynamic>> bucket) {
    final cts = DateTime.tryParse(candidate['createdAt']?.toString() ?? '');
    if (cts == null) return false;
    for (final r in bucket) {
      if (identical(r, candidate)) continue;
      final ts = DateTime.tryParse(r['createdAt']?.toString() ?? '');
      if (ts != null && ts.isAfter(cts)) return false;
    }
    return true;
  }

  static List<VitalsPoint> _vitalsSeries(List<Map<String, dynamic>> visits) {
    // Visits are newest-first; charts want oldest-first for left-to-right
    // time flow.
    final points = <VitalsPoint>[];
    for (final v in visits.reversed) {
      final dt = DateTime.tryParse(v['createdAt']?.toString() ?? '');
      if (dt == null) continue;
      final vitals = (v['vitals'] as Map?)?.cast<String, dynamic>() ?? {};
      final bp = vitals['bloodPressure']?.toString();
      double? sys;
      double? dia;
      if (bp != null && bp.contains('/')) {
        final parts = bp.split('/');
        sys = double.tryParse(parts[0].trim());
        dia = double.tryParse(parts[1].trim());
      }
      points.add(VitalsPoint(
        at: dt,
        temperature: (vitals['temperature'] as num?)?.toDouble(),
        systolic: sys,
        diastolic: dia,
        heartRate: (vitals['heartRate'] as num?)?.toDouble(),
        spo2: (vitals['spo2'] as num?)?.toDouble(),
        weight: (vitals['weight'] as num?)?.toDouble(),
      ));
    }
    return points;
  }
}

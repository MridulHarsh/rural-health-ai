import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/translations.dart';
import '../models/patient.dart';
import '../services/database_service.dart';
import '../services/fhir_service.dart';
import '../services/handoff_service.dart';
import '../services/outcome_service.dart';
import 'followup_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  Set<String> _assessmentsWithOutcomes = {};
  bool _isLoading = true;
  String _lang = 'en';

  String _t(String key) => AppTranslations.t(key, _lang);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('language') ?? 'en';
    final records = await DatabaseService.getAssessments();
    final outcomes = await OutcomeService.assessmentIdsWithOutcomes();
    if (!mounted) return;
    setState(() {
      _lang = lang;
      _records = records;
      _assessmentsWithOutcomes = outcomes;
      _isLoading = false;
    });
  }

  Color _riskColor(String? risk) {
    switch (risk) {
      case 'emergency':
        return const Color(0xFFDC2626);
      case 'urgent':
        return const Color(0xFFEA580C);
      case 'moderate':
        return const Color(0xFFF59E0B);
      case 'normal':
        return const Color(0xFF16A34A);
      default:
        return Colors.grey;
    }
  }

  /// Rebuild an AssessmentResult from the stored SQLite row so we can hand
  /// it to the follow-up screen and the FHIR builder without a second
  /// round-trip. This is a lossy reconstruction — image bytes and the
  /// tabular specialist screenings aren't persisted, only their paths /
  /// summary fields — but it's enough for the outcome-recording and FHIR
  /// handoff flows which only read patient + vitals + conditions + risk.
  AssessmentResult _fromRecord(Map<String, dynamic> r) {
    final patient = Patient(
      id: r['id']?.toString() ?? '',
      name: r['patientName']?.toString() ?? 'Unknown',
      age: (r['patientAge'] as int?) ?? 0,
      gender: r['patientGender']?.toString() ?? '',
      createdAt: DateTime.tryParse(r['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      householdId: r['householdId']?.toString(),
      abhaId: r['abhaId']?.toString(),
      abhaAddress: r['abhaAddress']?.toString(),
    );

    final vitalsMap = (r['vitals'] as Map?)?.cast<String, dynamic>() ?? {};
    final vitals = Vitals.fromJson(vitalsMap);

    final symptoms = (r['symptoms'] as List?)?.cast<String>() ?? const [];
    final nextSteps = (r['nextSteps'] as List?)?.cast<String>() ?? const [];

    final conditions = <PredictedCondition>[
      for (final c in (r['conditions'] as List? ?? const []))
        if (c is Map)
          PredictedCondition(
            // Pre-v3 rows have no `canonicalId` key. Fall back to 'unknown'
            // rather than munging the display name — "Dengue Fever" would
            // become `dengue_fever` but the real profile id is `dengue`,
            // so the munged key is garbage that would corrupt FHIR
            // Condition.code and analytics top_conditions alike. Honest
            // 'unknown' is safer than a plausible-looking fake id.
            canonicalId: c['canonicalId']?.toString() ?? 'unknown',
            name: c['name']?.toString() ?? 'Unknown',
            confidence: (c['confidence'] as num?)?.toDouble() ?? 0.0,
            riskLevel: _riskFromName(c['riskLevel']?.toString()),
            description: c['description']?.toString(),
            reasoning: c['reasoning']?.toString(),
            matchedCardinal:
                (c['matchedCardinal'] as List?)?.cast<String>() ?? const [],
            missingCardinal:
                (c['missingCardinal'] as List?)?.cast<String>() ?? const [],
            nextSteps: (c['nextSteps'] as List?)?.cast<String>() ?? const [],
          ),
    ];

    return AssessmentResult(
      patient: patient,
      vitals: vitals,
      symptoms: symptoms,
      conditions: conditions,
      overallRisk: _riskFromName(r['overallRisk']?.toString()),
      nextSteps: nextSteps,
      imagePath: r['imagePath']?.toString(),
      voiceTranscript: r['voiceTranscript']?.toString(),
      additionalNotes: r['notes']?.toString(),
      assessedAt: patient.createdAt,
    );
  }

  RiskLevel _riskFromName(String? name) {
    return RiskLevel.values.firstWhere(
      (r) => r.name == name,
      orElse: () => RiskLevel.normal,
    );
  }

  Future<void> _recordOutcome(Map<String, dynamic> record) async {
    final result = _fromRecord(record);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FollowupScreen(assessment: result),
      ),
    );
    if (!mounted) return;
    if (saved == true) _load();
  }

  Future<void> _shareFhir(Map<String, dynamic> record) async {
    final result = _fromRecord(record);
    final bundle = FhirBundleService.buildBundle(result);
    final json = FhirBundleService.toJsonString(bundle);
    final hash = FhirBundleService.computeHash(bundle);
    final ok = await HandoffService.shareFhirBundle(
      bundleJson: json,
      bundleHash: hash,
      subject: _t('share_fhir_bundle'),
      messageBody: '${_t('fhir_bundle_message')}${hash.substring(0, 12)}…',
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('fhir_bundle_share_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('patient_history'))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(_t('no_history'),
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  itemBuilder: (context, index) {
                    final record = _records[index];
                    final risk = record['overallRisk'] as String?;
                    final riskColor = _riskColor(risk);
                    final symptoms =
                        (record['symptoms'] as List?)?.cast<String>() ?? [];
                    final createdAt = record['createdAt'] != null
                        ? DateTime.tryParse(record['createdAt'])
                        : null;
                    final assessmentId = record['id']?.toString() ?? '';
                    final hasOutcome =
                        _assessmentsWithOutcomes.contains(assessmentId);
                    final followupDue = createdAt != null &&
                        OutcomeService.isFollowupDue(
                          assessmentDate: createdAt,
                          hasOutcome: hasOutcome,
                        );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Risk badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: riskColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    (risk ?? 'unknown').toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: riskColor,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (followupDue)
                                  _statusBadge(
                                    label: _t('followup_due'),
                                    color: const Color(0xFFD97706),
                                    icon: Icons.schedule_rounded,
                                  )
                                else if (hasOutcome)
                                  _statusBadge(
                                    label: _t('followup_recorded'),
                                    color: const Color(0xFF16A34A),
                                    icon: Icons.check_circle_outline,
                                  ),
                                const Spacer(),
                                if (createdAt != null)
                                  Text(
                                    '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              record['patientName'] ?? 'Unknown',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Age: ${record['patientAge'] ?? '-'} • ${record['patientGender'] ?? '-'}',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600),
                            ),
                            if (symptoms.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: symptoms.take(5).map((s) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(_t(s),
                                        style: const TextStyle(fontSize: 11)),
                                  );
                                }).toList(),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _recordOutcome(record),
                                    icon: Icon(
                                        hasOutcome
                                            ? Icons.edit_note_rounded
                                            : Icons.fact_check_outlined,
                                        size: 18),
                                    label: Text(
                                      _t('record_outcome'),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _shareFhir(record),
                                    icon: const Icon(Icons.share_outlined,
                                        size: 18),
                                    label: Text(
                                      _t('share_fhir_bundle'),
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ).animate()
                        .fadeIn(delay: (index * 80).ms, duration: 300.ms)
                        .slideY(begin: 0.05);
                  },
                ),
    );
  }

  Widget _statusBadge({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

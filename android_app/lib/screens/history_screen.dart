import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/translations.dart';
import '../models/patient.dart';
import '../services/database_service.dart';
import '../services/fhir_service.dart';
import '../services/handoff_service.dart';
import '../services/outcome_service.dart';
import '../services/patient_history_service.dart';
import 'followup_screen.dart';
import 'household_screen.dart';
import 'patient_timeline_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  List<PatientTimeline> _timelines = const [];
  Set<String> _assessmentsWithOutcomes = {};
  bool _isLoading = true;
  bool _groupByPatient = false;
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
    final timelines = await PatientHistoryService.listTimelines();
    if (!mounted) return;
    setState(() {
      _lang = lang;
      _records = records;
      _timelines = timelines;
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
    final outcome = await HandoffService.shareFhirOrQueue(
      bundleJson: json,
      bundleHash: hash,
      subject: _t('share_fhir_bundle'),
      messageBody: '${_t('fhir_bundle_message')}${hash.substring(0, 12)}…',
      label: 'FHIR — ${result.patient.name}',
    );
    if (!mounted) return;
    switch (outcome) {
      case HandoffResult.launched:
        break;
      case HandoffResult.queued:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('handoff_queued_to_outbox')),
            action: SnackBarAction(
              label: _t('view'),
              onPressed: () => Navigator.pushNamed(context, '/outbox'),
            ),
          ),
        );
        break;
      case HandoffResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('fhir_bundle_share_failed'))),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('patient_history')),
        actions: [
          if (_records.isNotEmpty)
            PopupMenuButton<bool>(
              icon: Icon(_groupByPatient
                  ? Icons.person_rounded
                  : Icons.event_rounded),
              tooltip: _t('history_group_by_tooltip'),
              onSelected: (v) => setState(() => _groupByPatient = v),
              itemBuilder: (ctx) => [
                CheckedPopupMenuItem(
                  value: false,
                  checked: !_groupByPatient,
                  child: Text(_t('history_group_by_date')),
                ),
                CheckedPopupMenuItem(
                  value: true,
                  checked: _groupByPatient,
                  child: Text(_t('history_group_by_patient')),
                ),
              ],
            ),
        ],
      ),
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
              : _groupByPatient
                  ? _buildPatientGroupedView()
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
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: _secondaryAction(
                                    icon: Icons.timeline_rounded,
                                    label: _t('patient_timeline'),
                                    onTap: () => _openTimeline(record),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _secondaryAction(
                                    icon: Icons.groups_rounded,
                                    label: _t('household_view'),
                                    onTap: (record['householdId']
                                                ?.toString()
                                                .isNotEmpty ??
                                            false)
                                        ? () => _openHousehold(record)
                                        : null,
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

  Widget _secondaryAction({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFF1F5F9) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: enabled
                    ? Colors.grey.shade700
                    : Colors.grey.shade400),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? Colors.grey.shade800
                      : Colors.grey.shade400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTimeline(Map<String, dynamic> record) {
    final identity = PatientHistoryService.identityForRow(record);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PatientTimelineScreen(identity: identity),
      ),
    );
  }

  void _openHousehold(Map<String, dynamic> record) {
    final hh = record['householdId']?.toString();
    if (hh == null || hh.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HouseholdScreen(householdId: hh),
      ),
    );
  }

  Widget _buildPatientGroupedView() {
    if (_timelines.isEmpty) {
      return Center(
        child: Text(_t('no_history'),
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _timelines.length,
      itemBuilder: (context, i) {
        final t = _timelines[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    PatientTimelineScreen(identity: t.identity),
              ),
            ),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _riskColor(t.latestRisk)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          (t.latestRisk ?? 'unknown').toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _riskColor(t.latestRisk),
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${t.visitCount} ${_t('visits')}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.identity.displayName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_t('age')}: ${t.identity.latestAge} • ${t.identity.gender.isEmpty ? '-' : t.identity.gender}',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600),
                  ),
                  if (t.lastVisit != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${_t('last_visit')}: ${t.lastVisit!.day}/${t.lastVisit!.month}/${t.lastVisit!.year}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                  if (t.identity.isApproximate) ...[
                    const SizedBox(height: 6),
                    Text(
                      _t('timeline_approx_match_warning'),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade800,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
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

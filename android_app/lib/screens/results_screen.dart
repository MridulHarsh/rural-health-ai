import 'dart:io';
// results_screen.dart
// Displays clinical engine results with red flag alerts,
// reasoning, missing symptom prompts, and actionable next steps.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../l10n/translations.dart';
import '../models/patient.dart';
import '../services/database_service.dart';
import '../services/specialist_models.dart';
import '../services/ml_service.dart';
import '../services/pdf_service.dart';
import '../services/handoff_service.dart';
import '../services/emergency_service.dart';

class ResultsScreen extends StatefulWidget {
  final AssessmentResult result;
  final String langCode;

  const ResultsScreen({
    super.key,
    required this.result,
    required this.langCode,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    // Fire the emergency alarm immediately when a red-flag triage lands here.
    // This is the "don't miss it" signal — vibration is enough to alert the
    // worker even if they've put the phone down.
    if (widget.result.overallRisk == RiskLevel.emergency ||
        widget.result.redFlag != null) {
      EmergencyService.triggerAlarm();
    }
  }

  @override
  void dispose() {
    EmergencyService.cancel();
    super.dispose();
  }

  String _t(String key) => AppTranslations.t(key, widget.langCode);

  Future<void> _sendToPhc() async {
    final r = widget.result;
    final buf = StringBuffer();
    buf.writeln('ASHA Referral — Rural Health AI');
    buf.writeln('Patient: ${r.patient.name}, age ${r.patient.age}, ${r.patient.gender}');
    buf.writeln('Risk: ${r.overallRisk.name.toUpperCase()}');
    if (r.redFlag != null) {
      buf.writeln('⚠ RED FLAG: ${r.redFlag!.conditionName}');
      buf.writeln('Action: ${r.redFlag!.immediateAction}');
    }
    if (r.conditions.isNotEmpty) {
      buf.writeln('Differential:');
      for (var i = 0; i < r.conditions.length && i < 3; i++) {
        final c = r.conditions[i];
        buf.writeln('  ${i + 1}. ${c.name} (${(c.confidence * 100).round()}%)');
      }
    }
    if (r.symptoms.isNotEmpty) {
      buf.writeln('Symptoms: ${r.symptoms.take(8).join(', ')}');
    }
    buf.writeln('Sent from Rural Health AI');
    final ok = await HandoffService.sendToWhatsApp(message: buf.toString());
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp not available on this device')),
      );
    }
  }

  Future<void> _draftEmergencySms() async {
    final r = widget.result;
    final buf = StringBuffer();
    buf.write('EMERGENCY: ');
    if (r.redFlag != null) {
      buf.write('${r.redFlag!.conditionName}. ');
    } else if (r.conditions.isNotEmpty) {
      buf.write('Suspected ${r.conditions.first.name}. ');
    }
    buf.write('Patient ${r.patient.name}, age ${r.patient.age}. ');
    buf.write('Need urgent transport.');
    await HandoffService.draftSms(message: buf.toString());
  }

  Future<void> _dial108() async {
    await HandoffService.dial(HandoffService.defaultEmergencyNumber);
  }

  // ── Risk colors ──
  Color _riskColor(RiskLevel risk) {
    switch (risk) {
      case RiskLevel.emergency:
        return const Color(0xFFDC2626);
      case RiskLevel.urgent:
        return const Color(0xFFEA580C);
      case RiskLevel.moderate:
        return const Color(0xFFF59E0B);
      case RiskLevel.normal:
        return const Color(0xFF16A34A);
    }
  }

  Color _riskBgColor(RiskLevel risk) {
    switch (risk) {
      case RiskLevel.emergency:
        return const Color(0xFFFEE2E2);
      case RiskLevel.urgent:
        return const Color(0xFFFFF7ED);
      case RiskLevel.moderate:
        return const Color(0xFFFEFCE8);
      case RiskLevel.normal:
        return const Color(0xFFF0FDF4);
    }
  }

  IconData _riskIcon(RiskLevel risk) {
    switch (risk) {
      case RiskLevel.emergency:
        return Icons.warning_rounded;
      case RiskLevel.urgent:
        return Icons.priority_high_rounded;
      case RiskLevel.moderate:
        return Icons.access_time_rounded;
      case RiskLevel.normal:
        return Icons.check_circle_rounded;
    }
  }

  String _riskLabel(RiskLevel risk) {
    switch (risk) {
      case RiskLevel.emergency:
        return _t('emergency');
      case RiskLevel.urgent:
        return _t('urgent');
      case RiskLevel.moderate:
        return 'Moderate';
      case RiskLevel.normal:
        return _t('normal');
    }
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final risk = widget.result.overallRisk;
    final riskColor = _riskColor(risk);
    final hasRedFlag = widget.result.redFlag != null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Risk-colored app bar ──
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: riskColor,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _riskLabel(risk),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      riskColor,
                      riskColor.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    _riskIcon(risk),
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── RED FLAG ALERT ──
                if (hasRedFlag) ...[
                  _buildRedFlagBanner(),
                  const SizedBox(height: 20),
                ],

                // ── PATIENT SUMMARY ──
                _buildPatientSummary(),
                const SizedBox(height: 20),

                // ── BODY SYSTEMS ──
                if (widget.result.implicatedSystems.isNotEmpty) ...[
                  _buildSystemsChips(),
                  const SizedBox(height: 20),
                ],

                // ── CONDITIONS ──
                if (widget.result.conditions.isNotEmpty) ...[
                  Text(
                    'Possible Conditions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...widget.result.conditions.asMap().entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildConditionCard(
                        entry.value,
                        rank: entry.key + 1,
                      ),
                    );
                  }),
                ] else ...[
                  _buildNoConditionsCard(),
                ],

                const SizedBox(height: 12),

                // ── NEXT STEPS (overall) ──
                if (widget.result.nextSteps.isNotEmpty)
                  _buildNextStepsCard(),

                const SizedBox(height: 12),

                // ── IMAGE CLASSIFICATION RESULTS ──
                _buildImageResultsSection(),

                // ── SPECIALIST SCREENINGS (heart, diabetes, kidney, etc.) ──
                _buildSpecialistSection(),

                const SizedBox(height: 24),

                // ── ACTION BUTTONS ──
                _buildActionButtons(),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // RED FLAG BANNER
  // ================================================================

  Widget _buildRedFlagBanner() {
    final rf = widget.result.redFlag!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠️ RED FLAG',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFDC2626),
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      rf.conditionName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7F1D1D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              rf.immediateAction,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF991B1B),
                height: 1.5,
              ),
            ),
          ),
          if (rf.triggerSymptoms.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: rf.triggerSymptoms.map((s) {
                return Chip(
                  label: Text(
                    _humanize(s),
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF991B1B)),
                  ),
                  backgroundColor: const Color(0xFFFECACA),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  labelPadding: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).shake(
          delay: 300.ms,
          duration: 500.ms,
          hz: 3,
          offset: const Offset(2, 0),
        );
  }

  // ================================================================
  // PATIENT SUMMARY
  // ================================================================

  Widget _buildPatientSummary() {
    final p = widget.result.patient;
    final v = widget.result.vitals;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                '${p.name}, ${p.age} yrs, ${p.gender}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (widget.result.symptoms.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: widget.result.symptoms.map((s) {
                return Chip(
                  label: Text(_humanize(s),
                      style: const TextStyle(fontSize: 11)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  labelPadding: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                );
              }).toList(),
            ),
          ],
          if (_hasVitals(v)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              children: [
                if (v.temperature != null)
                  _vitalChip('🌡️ ${v.temperature}°F'),
                if (v.bloodPressure != null)
                  _vitalChip('❤️ ${v.bloodPressure}'),
                if (v.heartRate != null)
                  _vitalChip('💓 ${v.heartRate} bpm'),
                if (v.spo2 != null) _vitalChip('🫁 ${v.spo2}%'),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  bool _hasVitals(Vitals v) =>
      v.temperature != null ||
      v.bloodPressure != null ||
      v.heartRate != null ||
      v.spo2 != null;

  Widget _vitalChip(String text) {
    return Text(text,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade700));
  }

  // ================================================================
  // BODY SYSTEMS CHIPS
  // ================================================================

  Widget _buildSystemsChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Affected Systems',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: widget.result.implicatedSystems.map((sys) {
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                sys,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue.shade800,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ================================================================
  // CONDITION CARD — the core display
  // ================================================================

  Widget _buildConditionCard(PredictedCondition condition, {required int rank}) {
    final color = _riskColor(condition.riskLevel);
    final bgColor = _riskBgColor(condition.riskLevel);
    final pct = (condition.confidence * 100).round();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: rank + name + confidence gauge ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                // Rank badge
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + risk label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        condition.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _riskLabel(condition.riskLevel),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: color,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Confidence gauge
                CircularPercentIndicator(
                  radius: 28,
                  lineWidth: 5,
                  percent: condition.confidence.clamp(0, 1),
                  center: Text(
                    '$pct%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  progressColor: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                  circularStrokeCap: CircularStrokeCap.round,
                ),
              ],
            ),
          ),

          // ── Body: description, reasoning, missing symptoms, next steps ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description
                if (condition.description != null) ...[
                  Text(
                    condition.description!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Clinical reasoning
                if (condition.reasoning != null &&
                    condition.reasoning!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.psychology_outlined,
                            size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            condition.reasoning!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade900,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Missing cardinal symptoms — "Ask about..."
                if (condition.missingCardinal.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.help_outline_rounded,
                            size: 16, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ask patient about:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children:
                                    condition.missingCardinal.map((s) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _humanize(s),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Per-condition next steps
                if (condition.nextSteps.isNotEmpty) ...[
                  Text(
                    'Recommended Actions:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...condition.nextSteps.map((step) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Icon(
                              Icons.arrow_right_rounded,
                              size: 16,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              step,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: (rank * 100).ms).slideY(
          begin: 0.1,
          end: 0,
          duration: 300.ms,
          delay: (rank * 100).ms,
        );
  }

  // ================================================================
  // NO CONDITIONS CARD
  // ================================================================

  Widget _buildNoConditionsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Unable to determine a specific condition',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Please refer the patient to a doctor for examination. '
            'Try adding more symptoms or vitals for a better assessment.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ================================================================
  // OVERALL NEXT STEPS
  // ================================================================

  Widget _buildNextStepsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded,
                  size: 18, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(
                _t('next_steps'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...widget.result.nextSteps.map((step) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ',
                      style: TextStyle(
                          fontSize: 14, color: Colors.green.shade700)),
                  Expanded(
                    child: Text(
                      step,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ================================================================
  // ACTION BUTTONS
  // ================================================================

  Widget _buildActionButtons() {
    final isEmergency =
        widget.result.overallRisk == RiskLevel.emergency ||
            widget.result.redFlag != null;
    return Column(
      children: [
        // Emergency row — only when red-flag or emergency risk
        if (isEmergency)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _dial108,
                  icon: const Icon(Icons.phone_in_talk_rounded),
                  label: const Text('Dial 108'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _draftEmergencySms,
                  icon: const Icon(Icons.sms_rounded),
                  label: const Text('SMS PHC'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade500,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        if (isEmergency) const SizedBox(height: 12),

        // PHC handoff — full-width primary secondary action.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _sendToPhc,
            icon: const Icon(Icons.send_rounded, size: 20),
            label: const Text('Send summary to PHC'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Save button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaved ? null : _saveAssessment,
            icon: Icon(_isSaved ? Icons.check_rounded : Icons.save_outlined),
            label: Text(_isSaved ? 'Saved' : _t('save_record')),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // PDF + New Assessment row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                label: Text(_t('export_pdf')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(_t('new_assessment')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ================================================================
  // ACTIONS
  // ================================================================

  Future<void> _saveAssessment() async {
    try {
      await DatabaseService.saveAssessment(widget.result.toJson());
      if (!mounted) return;
      setState(() => _isSaved = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Assessment saved successfully'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportPdf() async {
    try {
      await PdfExportService.printSummary(widget.result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _humanize(String key) =>
      key.replaceAll('_', ' ').replaceFirst(key[0], key[0].toUpperCase());


  // ── Specialist Screening Section ──
  Widget _buildImageResultsSection() {
    final results = widget.result.imageClassificationResults;
    final imageType = widget.result.imageType;
    if (results == null || results.isEmpty || imageType == null) {
      return const SizedBox.shrink();
    }

    final typeLabel = {
      'eye': 'Eye Disease Screening',
      'lung': 'Chest X-ray Analysis',
      'malaria': 'Malaria Smear Analysis',
      'skin': 'Skin Triage Screening',
    }[imageType] ?? 'Image Analysis';

    // The skin classifier prepends a sentinel MapEntry when top-1 probability
    // falls below MLService.skinConfidenceFloor. In that case we suppress the
    // confident-looking ranked list entirely and show a referral banner; the
    // ranked alternatives below are informational-only.
    final hasLowConfSentinel =
        results.first.key == MLService.skinLowConfidenceLabel;
    final renderedResults = hasLowConfSentinel
        ? results.where((r) => r.key != MLService.skinLowConfidenceLabel).toList()
        : results;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image_search, color: Colors.indigo.shade600, size: 22),
              const SizedBox(width: 8),
              Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.indigo.shade800,
                ),
              ),
            ],
          ),
          if (hasLowConfSentinel) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.amber.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preliminary — please confirm at PHC',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'The AI is not confident about this skin image. '
                          'Alternatives below are informational only.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...renderedResults.map((r) {
            final pct = (r.value * 100).toStringAsFixed(1);
            // When the sentinel is present we refuse to highlight any row as
            // "top" — the model isn't confident enough to pick a winner.
            final isTop = !hasLowConfSentinel && r == renderedResults.first;
            final confidence = r.value;
            final barColor = confidence > 0.7
                ? Colors.red.shade600
                : confidence > 0.4
                    ? Colors.orange.shade600
                    : Colors.green.shade600;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        r.key.replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isTop ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isTop ? barColor : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: confidence,
                      backgroundColor: Colors.grey.shade200,
                      color: isTop ? barColor : Colors.grey.shade400,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
          // Clinical guidance for the top prediction — skipped entirely when
          // the model flagged low confidence, because the top label is then
          // a PHC-referral sentinel (no guidance entry to look up anyway).
          if (!hasLowConfSentinel)
            _buildImageClassGuidance(
                renderedResults.first.key, renderedResults.first.value),
          if (widget.result.imagePath != null &&
              File(widget.result.imagePath!).existsSync()) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(widget.result.imagePath!),
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.grey.shade100,
                  alignment: Alignment.center,
                  child: Icon(Icons.broken_image,
                      color: Colors.grey.shade400, size: 40),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'This is an AI screening tool — not a medical diagnosis. Refer to a doctor for confirmation.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// Static clinical guidance for image-classified conditions. Maps each
  /// canonical label (as emitted by MLService._canonicalizeImageClass) to a
  /// short description and the steps an ASHA worker should take.
  static const Map<String, Map<String, Object>> _imageClassGuidance = {
    // Eye
    'Cataract': {
      'description':
          'Clouding of the eye lens causing blurred, cloudy, or dim vision. Usually age-related and treatable with surgery.',
      'steps': [
        'Refer to an ophthalmologist for confirmation',
        'Surgical replacement of the lens is the definitive treatment',
        'Advise UV-protective sunglasses and blood-sugar control',
      ],
    },
    'Diabetic Retinopathy': {
      'description':
          'Diabetes-related damage to retinal blood vessels. Leading cause of preventable blindness in working-age adults.',
      'steps': [
        'Urgent ophthalmology referral for retinal examination',
        'Tight glycemic control (HbA1c target <7%) and BP control',
        'Annual dilated fundus examination for all diabetic patients',
      ],
    },
    'Glaucoma': {
      'description':
          'Optic nerve damage, usually from raised intraocular pressure. Irreversible vision loss if untreated.',
      'steps': [
        'Refer to ophthalmologist for IOP measurement and visual-field test',
        'Lifelong IOP-lowering eye drops are typically required',
        'Screen first-degree relatives (strong hereditary risk)',
      ],
    },
    // Lung
    'Pneumonia': {
      'description':
          'Infection of the lung parenchyma. Common, serious in children and the elderly.',
      'steps': [
        'Check SpO2 — refer urgently if <92% or respiratory rate elevated',
        'Empirical antibiotics per local protocol if bacterial',
        'Supportive care: fluids, oxygen, antipyretics',
      ],
    },
    'Tuberculosis': {
      'description':
          'Mycobacterial infection, most commonly pulmonary. Notifiable disease in India; free treatment under NTEP.',
      'steps': [
        'Sputum microscopy / CBNAAT for confirmation',
        'Notify case and initiate DOTS treatment at PHC',
        'Screen household contacts; BCG status review',
      ],
    },
    'COVID-19': {
      'description':
          'SARS-CoV-2 respiratory infection. Severity ranges from mild cold-like symptoms to ARDS.',
      'steps': [
        'Isolate patient and use mask/PPE',
        'Monitor SpO2 at rest and after 6-minute walk',
        'Refer if SpO2 <94%, persistent high fever, or breathlessness',
      ],
    },
    'Normal': {
      'description':
          'The screening model found no obvious abnormality. This is not a diagnosis — clinical correlation is required.',
      'steps': [
        'Correlate with symptoms and vitals',
        'If symptoms persist, refer for physician evaluation',
      ],
    },
    // Malaria
    'Parasitized (malaria detected)': {
      'description':
          'Malaria parasites detected on the blood smear. Confirm with RDT and species identification.',
      'steps': [
        'Start anti-malarial treatment per NVBDCP guidelines (species-specific)',
        'Watch for severe features: altered sensorium, jaundice, bleeding, hypotension',
        'Refer immediately if severe or in pregnancy',
      ],
    },
    'Uninfected': {
      'description':
          'No malaria parasites detected in this smear. Does not rule out malaria — repeat testing if fever recurs.',
      'steps': [
        'If fever persists, repeat smear/RDT every 12–24 hours',
        'Consider alternative causes: dengue, typhoid, viral fever',
      ],
    },
  };

  Widget _buildImageClassGuidance(String label, double confidence) {
    final entry = _imageClassGuidance[label];
    // Don't render guidance for low-confidence top picks — misleading.
    if (entry == null || confidence < 0.4) return const SizedBox.shrink();
    final description = entry['description'] as String;
    final steps = (entry['steps'] as List).cast<String>();
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: TextStyle(fontSize: 12.5, color: Colors.indigo.shade900, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            'Suggested next steps',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.indigo.shade700,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 4),
          ...steps.map((s) => Padding(
                padding: const EdgeInsets.only(top: 2, left: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ',
                        style: TextStyle(color: Colors.indigo.shade700, fontSize: 12)),
                    Expanded(
                      child: Text(s,
                          style: TextStyle(fontSize: 12, color: Colors.indigo.shade900, height: 1.35)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSpecialistSection() {
    final screenings = widget.result.specialistScreenings;
    if (screenings.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(children: [
          Icon(Icons.biotech, color: Colors.deepPurple.shade400, size: 22),
          const SizedBox(width: 8),
          Text('Specialist Screenings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
              color: Colors.deepPurple.shade700)),
        ]),
        const SizedBox(height: 4),
        Text('Based on patient vitals & demographics',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ...screenings.map(_buildScreeningCard),
      ],
    );
  }

  Widget _buildScreeningCard(SpecialistScreening s) {
    final Color rc;
    final IconData ri;
    if (s.riskLabel == 'High Risk') {
      rc = Colors.red.shade400; ri = Icons.warning_rounded;
    } else if (s.riskLabel == 'Moderate Risk') {
      rc = Colors.orange.shade400; ri = Icons.info_rounded;
    } else {
      rc = Colors.green.shade400; ri = Icons.check_circle_rounded;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10), elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: rc.withValues(alpha: 0.3))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(width: 48, height: 48,
            decoration: BoxDecoration(
              color: rc.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(ri, color: rc, size: 26)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.modelName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(s.riskLabel, style: TextStyle(color: rc, fontWeight: FontWeight.w500, fontSize: 13)),
            ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: rc.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Text('${(s.riskScore * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: rc, fontWeight: FontWeight.bold, fontSize: 14))),
        ]),
      ),
    );
  }

}

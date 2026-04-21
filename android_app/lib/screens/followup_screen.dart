// followup_screen.dart
// Follow-up outcome capture. Route here from the history list's "Record
// outcome" CTA or from the amber "Follow-up due" badge. Persists a
// FollowupOutcome via OutcomeService and, when the consent checkbox is
// ticked, appends a de-identified record to the analytics JSONL.
//
// Feature #3 in the NeuCure roadmap.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../l10n/translations.dart';
import '../models/followup_outcome.dart';
import '../models/patient.dart';
import '../services/analytics_exporter.dart';
import '../services/outcome_service.dart';

class FollowupScreen extends StatefulWidget {
  /// The assessment being followed up on. We accept the full
  /// [AssessmentResult] (not just the ID) so the analytics exporter can
  /// emit the de-identified record without a second SQLite round-trip.
  final AssessmentResult assessment;

  const FollowupScreen({super.key, required this.assessment});

  @override
  State<FollowupScreen> createState() => _FollowupScreenState();
}

class _FollowupScreenState extends State<FollowupScreen> {
  static const _uuid = Uuid();

  final _diagnosisCtrl = TextEditingController();
  final _treatmentCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  Adherence _adherence = Adherence.unknown;
  OutcomeStatus _outcomeStatus = OutcomeStatus.improving;
  DateTime _followupDate = DateTime.now();
  bool _consentToShare = false;
  bool _saving = false;

  String _lang = 'en';
  String _t(String key) => AppTranslations.t(key, _lang);

  @override
  void initState() {
    super.initState();
    _loadLang();
  }

  Future<void> _loadLang() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _lang = prefs.getString('language') ?? 'en');
  }

  @override
  void dispose() {
    _diagnosisCtrl.dispose();
    _treatmentCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    // Follow-ups can't be in the future (ASHA records what already happened)
    // and shouldn't predate the original assessment.
    final picked = await showDatePicker(
      context: context,
      initialDate: _followupDate,
      firstDate: widget.assessment.assessedAt,
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _followupDate = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final outcome = FollowupOutcome(
      id: _uuid.v4(),
      assessmentId: widget.assessment.patient.id,
      followupDate: _followupDate,
      actualDiagnosis: _diagnosisCtrl.text.trim().isEmpty
          ? null
          : _diagnosisCtrl.text.trim(),
      treatmentGiven: _treatmentCtrl.text.trim().isEmpty
          ? null
          : _treatmentCtrl.text.trim(),
      adherence: _adherence,
      outcomeStatus: _outcomeStatus,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      consentToShare: _consentToShare,
    );

    String? errorMsg;
    try {
      await OutcomeService.save(outcome);
      // Analytics export is fire-and-forget — a JSONL append failure
      // should not block the save-outcome success path. The caller knows
      // consent was ticked if they tap "Export" from Settings later.
      if (_consentToShare) {
        await AnalyticsExporter.record(
          result: widget.assessment,
          outcome: outcome,
        );
      }
    } catch (_) {
      errorMsg = _t('outcome_save_failed');
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('outcome_saved'))),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_t('followup_title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _patientHeader(theme),
            const SizedBox(height: 20),
            _dateField(),
            const SizedBox(height: 16),
            _textField(
              label: _t('actual_diagnosis'),
              hint: _t('actual_diagnosis_hint'),
              controller: _diagnosisCtrl,
            ),
            const SizedBox(height: 16),
            _textField(
              label: _t('treatment_given'),
              hint: _t('treatment_given_hint'),
              controller: _treatmentCtrl,
            ),
            const SizedBox(height: 20),
            _sectionLabel(_t('adherence')),
            const SizedBox(height: 8),
            _adherenceChips(),
            const SizedBox(height: 20),
            _sectionLabel(_t('outcome_status')),
            const SizedBox(height: 8),
            _outcomeChips(),
            const SizedBox(height: 16),
            _textField(
              label: _t('followup_notes'),
              hint: _t('followup_notes_hint'),
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 20),
            _consentCard(theme),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_t('save_outcome')),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _patientHeader(ThemeData theme) {
    final p = widget.assessment.patient;
    final top = widget.assessment.conditions.isNotEmpty
        ? widget.assessment.conditions.first.name
        : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            'Age ${p.age} • ${p.gender}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (top != null) ...[
            const SizedBox(height: 8),
            Text('AI top prediction: $top',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ],
      ),
    );
  }

  Widget _dateField() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: _t('followup_date'),
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          '${_followupDate.day}/${_followupDate.month}/${_followupDate.year}',
        ),
      ),
    );
  }

  Widget _textField({
    required String label,
    required String hint,
    required TextEditingController controller,
    int? minLines,
    int? maxLines,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines ?? 1,
      maxLines: maxLines ?? 1,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      );

  Widget _adherenceChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in Adherence.values)
          ChoiceChip(
            label: Text(_t('adherence_${a.name}')),
            selected: _adherence == a,
            onSelected: (_) => setState(() => _adherence = a),
          ),
      ],
    );
  }

  Widget _outcomeChips() {
    // The enum name for `referredFurther` is camelCase — the translation
    // keys use snake_case, so map explicitly rather than relying on string
    // munging which would silently break when a new enum value is added.
    const keyByStatus = {
      OutcomeStatus.resolved: 'outcome_resolved',
      OutcomeStatus.improving: 'outcome_improving',
      OutcomeStatus.worse: 'outcome_worse',
      OutcomeStatus.referredFurther: 'outcome_referred_further',
      OutcomeStatus.noPhcVisit: 'outcome_no_phc_visit',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in OutcomeStatus.values)
          ChoiceChip(
            label: Text(_t(keyByStatus[s] ?? s.name)),
            selected: _outcomeStatus == s,
            onSelected: (_) => setState(() => _outcomeStatus = s),
          ),
      ],
    );
  }

  Widget _consentCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: _consentToShare,
                onChanged: (v) =>
                    setState(() => _consentToShare = v ?? false),
              ),
              Expanded(
                child: Text(
                  _t('consent_share_deidentified'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4, top: 2),
            child: Text(
              _t('consent_share_deidentified_body'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

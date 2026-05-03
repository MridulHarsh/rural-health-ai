// followup_outcome.dart
// A longitudinal outcome recorded by the ASHA after re-contacting the patient
// (typically 7 or 30 days after the original encounter). Closes the loop on
// a prior AssessmentResult — what did the PHC actually diagnose, what
// treatment was given, and did the patient follow through.
//
// This is the raw material for real-world-evidence tracking (feature #3 in
// the NeuCure roadmap). The de-identified analytics export lives in
// analytics_exporter.dart — this file just models the per-encounter outcome.

/// Patient compliance with the treatment actually prescribed at the PHC.
enum Adherence {
  full,     // Took all doses / attended all follow-ups
  partial,  // Took some but missed doses / defaulted on schedule
  none,     // Did not start or abandoned immediately
  unknown,  // ASHA couldn't confirm — often: patient moved, no contact
}

/// The high-level trajectory between the original assessment and the
/// follow-up visit. Kept coarse on purpose: finer granularity would push
/// ASHA workers into judgment calls they can't reliably make in the field.
enum OutcomeStatus {
  resolved,         // Symptoms gone, no further care needed
  improving,        // Getting better but still under treatment
  worse,            // Same or worse despite treatment
  referredFurther,  // PHC referred to district hospital / specialist
  noPhcVisit,       // Patient never reached the PHC (often the honest answer)
}

/// A recorded follow-up outcome. One-to-many with AssessmentResult — the
/// same encounter can have a 7-day and a 30-day check-in.
class FollowupOutcome {
  final String id;
  final String assessmentId;
  final DateTime followupDate;
  /// Free-text diagnosis as given by the PHC physician. Encrypted at rest.
  /// Stays free-text rather than ICD-10 because ASHA workers paraphrase.
  final String? actualDiagnosis;
  /// Drug / procedure list as told to the ASHA. Encrypted at rest.
  final String? treatmentGiven;
  final Adherence adherence;
  final OutcomeStatus outcomeStatus;
  /// Additional context — transport barrier, household situation, etc.
  /// Encrypted at rest.
  final String? notes;
  /// If true, a de-identified record is appended to the analytics JSONL.
  /// Default false — consent must be explicit per the DPDP Act.
  final bool consentToShare;
  final DateTime createdAt;

  FollowupOutcome({
    required this.id,
    required this.assessmentId,
    required this.followupDate,
    this.actualDiagnosis,
    this.treatmentGiven,
    required this.adherence,
    required this.outcomeStatus,
    this.notes,
    this.consentToShare = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'assessmentId': assessmentId,
        'followupDate': followupDate.toIso8601String(),
        'actualDiagnosis': actualDiagnosis,
        'treatmentGiven': treatmentGiven,
        'adherence': adherence.name,
        'outcomeStatus': outcomeStatus.name,
        'notes': notes,
        'consentToShare': consentToShare,
        'createdAt': createdAt.toIso8601String(),
      };

  static Adherence adherenceFromName(String? name) =>
      Adherence.values.firstWhere(
        (a) => a.name == name,
        orElse: () => Adherence.unknown,
      );

  static OutcomeStatus statusFromName(String? name) =>
      OutcomeStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => OutcomeStatus.noPhcVisit,
      );
}

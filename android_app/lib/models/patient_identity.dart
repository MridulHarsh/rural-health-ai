// patient_identity.dart
// Stable key for grouping assessments that belong to the same patient across
// multiple visits. ABHA ID is the preferred identity — it's already an
// India-Stack identifier with a stable authority. The name-age-gender
// fallback handles the common rural case where the patient doesn't have an
// ABHA ID yet; it's approximate and surfaces a warning in the timeline UI
// (typos or age-at-visit drift can split one person into two lanes).

class PatientIdentity {
  /// `abha` when the identity comes from an ABHA ID; `approx` when it's
  /// derived from name + age + gender. UI uses this to display an "approx
  /// match" warning on the timeline.
  final String source;
  final String key;
  final String displayName;
  final int latestAge;
  final String gender;
  final String? abhaId;

  const PatientIdentity({
    required this.source,
    required this.key,
    required this.displayName,
    required this.latestAge,
    required this.gender,
    this.abhaId,
  });

  bool get isApproximate => source == 'approx';

  @override
  bool operator ==(Object other) =>
      other is PatientIdentity && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

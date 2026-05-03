// household_service.dart
// Cluster-level view over the `assessments` table, grouped by `household_id`.
// Surfaces contagion clusters that a single-patient view can never see —
// e.g. three members with fever in a week is a dengue/typhoid/malaria lead
// the ASHA would otherwise miss, and two members with scabies means the
// whole family needs treatment, not just the index case.
//
// Feature #5 (household contagion) in the NeuCure roadmap.

import 'database_service.dart';

/// A contagion alert surfaced by [HouseholdService]. The reason codes are
/// stable enum-like strings so the i18n layer can pick a localized label
/// without the service knowing about translations.
class ContagionAlert {
  /// Stable translation key (e.g. `household_alert_shared_contagious`,
  /// `household_alert_febrile_cluster`). Resolved against
  /// [AppTranslations] by the UI.
  final String reasonKey;

  /// Human-readable trigger detail — condition name or symptom label
  /// (e.g. "tuberculosis", "fever") in the underlying DiseaseProfile's
  /// canonical id form. UI renders this as supporting text.
  final String trigger;

  /// How many household members are affected.
  final int memberCount;

  /// Severity — drives the banner color. `critical` = contagious confirmed
  /// diagnosis shared across members; `warning` = heuristic cluster that
  /// needs investigation.
  final ContagionSeverity severity;

  /// Short next-step for the ASHA (e.g. "Screen all household contacts for
  /// TB", "Inspect water source"). Also a translation key.
  final String actionKey;

  const ContagionAlert({
    required this.reasonKey,
    required this.trigger,
    required this.memberCount,
    required this.severity,
    required this.actionKey,
  });
}

enum ContagionSeverity { critical, warning }

/// Summary of one household for the household list.
class HouseholdSummary {
  final String householdId;
  final int memberCount;
  final int visitCount;
  final DateTime? lastVisit;
  final int alertCount;
  final String? topMemberName; // Decrypted latest patient name — nullable

  const HouseholdSummary({
    required this.householdId,
    required this.memberCount,
    required this.visitCount,
    required this.lastVisit,
    required this.alertCount,
    this.topMemberName,
  });
}

/// One household member as the ASHA would see them — the most recent
/// assessment row per unique person in the household.
class HouseholdMember {
  final String assessmentId;
  final String name;
  final int age;
  final String gender;
  final String? topCondition;
  final String? risk;
  final DateTime? lastSeen;
  final List<String> symptoms;
  final String? abhaId;

  const HouseholdMember({
    required this.assessmentId,
    required this.name,
    required this.age,
    required this.gender,
    this.topCondition,
    this.risk,
    this.lastSeen,
    this.symptoms = const [],
    this.abhaId,
  });
}

class HouseholdService {
  /// Diseases that the clinical knowledge base treats as contagious within a
  /// household. Two hits in the same household triggers a critical alert —
  /// these are the profiles where "treat the whole family" is the textbook
  /// guidance, not an edge case.
  ///
  /// Grouped here (rather than as a flag on each `DiseaseProfile`) because
  /// it's a property of the epidemiology, not of the clinical scoring, and
  /// lifting it out keeps clinical_knowledge.dart from taking on an
  /// infection-control concern it doesn't otherwise have.
  static const Set<String> contagiousProfileIds = {
    // Respiratory — airborne or droplet
    'tuberculosis',
    'pneumonia',
    'influenza',
    'common_cold',
    'pharyngitis',
    'measles',
    'chickenpox',
    // Skin / contact
    'scabies',
    'fungal_skin',
    // GI — fecal-oral
    'gastroenteritis',
    'cholera',
    'typhoid',
    'hepatitis_a',
    'worm_infestation',
    // Vector-shared environment (not person-to-person but household-shared)
    'malaria',
    'dengue',
    'chikungunya',
    // ENT — contact
    'conjunctivitis',
    'otitis_media',
  };

  /// Feverish / respiratory / enteric cluster triggers. These are symptoms
  /// rather than diagnoses — the heuristic is "N members with symptom X in
  /// the last [windowDays] days."
  static const int _clusterMinCases = 2;
  static const Duration _clusterWindow = Duration(days: 7);

  /// Return one summary per distinct household_id. Drives the household
  /// list screen and the home-screen badge.
  static Future<List<HouseholdSummary>> listHouseholds() async {
    final all = await DatabaseService.getAssessments();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in all) {
      final hh = (r['householdId'] as String?)?.trim();
      if (hh == null || hh.isEmpty) continue;
      grouped.putIfAbsent(hh, () => []).add(r);
    }
    final summaries = <HouseholdSummary>[];
    for (final entry in grouped.entries) {
      final rows = entry.value;
      final members = _uniqueMembers(rows);
      final alerts = _buildAlerts(rows, members);
      DateTime? latest;
      String? topName;
      for (final r in rows) {
        final dt = DateTime.tryParse(r['createdAt']?.toString() ?? '');
        if (dt != null && (latest == null || dt.isAfter(latest))) {
          latest = dt;
          topName = r['patientName']?.toString();
        }
      }
      summaries.add(HouseholdSummary(
        householdId: entry.key,
        memberCount: members.length,
        visitCount: rows.length,
        lastVisit: latest,
        alertCount: alerts.length,
        topMemberName: topName,
      ));
    }
    summaries.sort((a, b) {
      // Households with alerts float to the top; then most-recent visit.
      if (a.alertCount != b.alertCount) {
        return b.alertCount.compareTo(a.alertCount);
      }
      final aTs = a.lastVisit?.millisecondsSinceEpoch ?? 0;
      final bTs = b.lastVisit?.millisecondsSinceEpoch ?? 0;
      return bTs.compareTo(aTs);
    });
    return summaries;
  }

  /// Total number of contagion alerts across ALL households — used by the
  /// home-screen badge. Cheap enough that we don't memoize.
  static Future<int> totalContagionAlertCount() async {
    final summaries = await listHouseholds();
    return summaries.fold<int>(0, (sum, s) => sum + s.alertCount);
  }

  /// All visits for a given household, newest first.
  static Future<List<Map<String, dynamic>>> visitsForHousehold(
      String householdId) async {
    return DatabaseService.getByHousehold(householdId);
  }

  /// One row per unique person in the household, picking the most recent
  /// assessment for each.
  static Future<List<HouseholdMember>> membersOfHousehold(
      String householdId) async {
    final rows = await DatabaseService.getByHousehold(householdId);
    return _uniqueMembers(rows);
  }

  /// Contagion alerts for a single household. Combines two signal types:
  ///  1. Two or more members diagnosed with the same contagious condition —
  ///     always `critical`.
  ///  2. Heuristic symptom clusters (febrile / enteric / respiratory) when
  ///     two or more members match in the last 7 days — `warning`.
  static Future<List<ContagionAlert>> alertsForHousehold(
      String householdId) async {
    final rows = await DatabaseService.getByHousehold(householdId);
    final members = _uniqueMembers(rows);
    return _buildAlerts(rows, members);
  }

  // ────────────────────────────────────────────────────────────

  static List<HouseholdMember> _uniqueMembers(
      List<Map<String, dynamic>> rows) {
    // Identity: ABHA id if present, else normalized name + age bucket +
    // gender. This matches the patient-timeline grouping so the same person
    // shows up consistently across both views.
    final byKey = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final key = _memberIdentityKey(r);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = r;
      } else {
        final existingTs =
            DateTime.tryParse(existing['createdAt']?.toString() ?? '');
        final thisTs = DateTime.tryParse(r['createdAt']?.toString() ?? '');
        if (thisTs != null &&
            (existingTs == null || thisTs.isAfter(existingTs))) {
          byKey[key] = r;
        }
      }
    }
    return byKey.values.map(_memberFromRow).toList();
  }

  static HouseholdMember _memberFromRow(Map<String, dynamic> r) {
    final symptoms = <String>[
      for (final s in (r['symptoms'] as List? ?? const []))
        if (s is String) s,
    ];
    final conditions = (r['conditions'] as List?) ?? const [];
    final topCondition = conditions.isNotEmpty && conditions.first is Map
        ? (conditions.first as Map)['name']?.toString()
        : null;
    return HouseholdMember(
      assessmentId: r['id']?.toString() ?? '',
      name: (r['patientName']?.toString().isNotEmpty ?? false)
          ? r['patientName'].toString()
          : 'Unknown',
      age: (r['patientAge'] as int?) ?? 0,
      gender: r['patientGender']?.toString() ?? '',
      topCondition: topCondition,
      risk: r['overallRisk']?.toString(),
      lastSeen: DateTime.tryParse(r['createdAt']?.toString() ?? ''),
      symptoms: symptoms,
      abhaId: r['abhaId']?.toString(),
    );
  }

  static String _memberIdentityKey(Map<String, dynamic> r) {
    final abha = (r['abhaId'] as String?)?.trim();
    if (abha != null && abha.isNotEmpty) return 'abha:$abha';
    final name = (r['patientName'] as String?)?.trim().toLowerCase() ?? '';
    final age = r['patientAge'];
    final gender = (r['patientGender'] as String?)?.trim().toLowerCase() ?? '';
    return 'np:$name|$age|$gender';
  }

  /// Translate grouped rows into the alert list. Takes `rows` AND the
  /// already-deduped member list so we don't double-count the same person
  /// visiting three times.
  static List<ContagionAlert> _buildAlerts(
      List<Map<String, dynamic>> rows, List<HouseholdMember> members) {
    final alerts = <ContagionAlert>[];
    final now = DateTime.now();
    final cutoff = now.subtract(_clusterWindow);

    // 1. Contagious diagnosis shared across members. We look at the top
    //    canonical condition on each member's most-recent assessment.
    final conditionToMembers = <String, Set<String>>{};
    for (final m in members) {
      final latestRow = rows.firstWhere(
        (r) => r['id']?.toString() == m.assessmentId,
        orElse: () => const {},
      );
      final conds = (latestRow['conditions'] as List?) ?? const [];
      for (final c in conds.take(3)) {
        if (c is! Map) continue;
        final canonical = c['canonicalId']?.toString();
        if (canonical == null || canonical.isEmpty) continue;
        if (!contagiousProfileIds.contains(canonical)) continue;
        conditionToMembers.putIfAbsent(canonical, () => {}).add(
            m.abhaId?.isNotEmpty == true ? m.abhaId! : m.name);
      }
    }
    for (final entry in conditionToMembers.entries) {
      if (entry.value.length >= _clusterMinCases) {
        alerts.add(ContagionAlert(
          reasonKey: 'household_alert_shared_contagious',
          trigger: entry.key,
          memberCount: entry.value.length,
          severity: ContagionSeverity.critical,
          actionKey: _actionForCondition(entry.key),
        ));
      }
    }

    // 2. Heuristic symptom clusters in the last 7 days. We scan ALL recent
    //    rows (not just most-recent-per-member) so three visits from three
    //    different siblings with fever all surface as one cluster.
    final febrile = <String>{}; // identity keys
    final enteric = <String>{};
    final respiratory = <String>{};
    for (final r in rows) {
      final dt = DateTime.tryParse(r['createdAt']?.toString() ?? '');
      if (dt == null || dt.isBefore(cutoff)) continue;
      final sym = <String>[
        for (final s in (r['symptoms'] as List? ?? const []))
          if (s is String) s,
      ];
      final key = _memberIdentityKey(r);
      if (_hasAny(sym, _fevers)) febrile.add(key);
      if (_hasAny(sym, _enteric)) enteric.add(key);
      if (_hasAny(sym, _respiratory)) respiratory.add(key);
    }
    if (febrile.length >= _clusterMinCases) {
      alerts.add(ContagionAlert(
        reasonKey: 'household_alert_febrile_cluster',
        trigger: 'fever',
        memberCount: febrile.length,
        severity: ContagionSeverity.warning,
        actionKey: 'household_action_febrile',
      ));
    }
    if (enteric.length >= _clusterMinCases) {
      alerts.add(ContagionAlert(
        reasonKey: 'household_alert_enteric_cluster',
        trigger: 'diarrhea',
        memberCount: enteric.length,
        severity: ContagionSeverity.warning,
        actionKey: 'household_action_enteric',
      ));
    }
    if (respiratory.length >= _clusterMinCases) {
      alerts.add(ContagionAlert(
        reasonKey: 'household_alert_respiratory_cluster',
        trigger: 'cough',
        memberCount: respiratory.length,
        severity: ContagionSeverity.warning,
        actionKey: 'household_action_respiratory',
      ));
    }
    return alerts;
  }

  static bool _hasAny(List<String> symptoms, Set<String> triggers) {
    for (final s in symptoms) {
      if (triggers.contains(s)) return true;
    }
    return false;
  }

  /// Which action key to show for each contagious-disease cluster. Keeps the
  /// translation key surface manageable — most conditions share an action
  /// template ("Treat all household contacts").
  static String _actionForCondition(String id) {
    switch (id) {
      case 'tuberculosis':
        return 'household_action_tb';
      case 'malaria':
      case 'dengue':
      case 'chikungunya':
        return 'household_action_vector';
      case 'scabies':
      case 'fungal_skin':
        return 'household_action_skin';
      case 'cholera':
      case 'typhoid':
      case 'hepatitis_a':
      case 'gastroenteritis':
      case 'worm_infestation':
        return 'household_action_enteric';
      default:
        return 'household_action_contagion';
    }
  }

  static const Set<String> _fevers = {
    'fever',
    'high_fever',
    'mild_fever',
    'chills',
    'night_sweats',
  };

  static const Set<String> _enteric = {
    'diarrhea',
    'vomiting',
    'abdominal_pain',
    'dehydration',
    'blood_in_stool',
    'watery_stools',
  };

  static const Set<String> _respiratory = {
    'cough',
    'breathlessness',
    'chest_tightness',
    'wheezing',
    'blood_in_sputum',
    'sore_throat',
  };
}

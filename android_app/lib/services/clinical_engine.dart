// clinical_engine.dart
// Diagnostic reasoning engine that mimics how a doctor thinks.
//
// Pipeline:
//   1. Normalize symptoms (aliases, voice input cleanup)
//   2. Check RED FLAGS → immediate triage, bypass everything
//   3. Classify body systems from symptom profile
//   4. Filter disease candidates to relevant systems
//   5. Score each candidate using clinical pattern matching
//   6. Adjust for demographics (age, sex) and regional prevalence
//   7. Optionally boost/adjust with TFLite ML confidence
//   8. Return ranked differential with risk level and next steps

import 'clinical_knowledge.dart';

/// The result of the diagnostic engine.
class DiagnosticResult {
  /// Did a red flag fire?
  final RedFlagMatch? redFlag;

  /// Ranked list of possible conditions (top 3-5).
  final List<CandidateCondition> conditions;

  /// Overall risk level (driven by highest-risk condition or red flag).
  final ClinicalRisk overallRisk;

  /// Body systems implicated by the symptoms.
  final List<BodySystem> implicatedSystems;

  /// Summary for the health worker.
  final String summary;

  DiagnosticResult({
    this.redFlag,
    required this.conditions,
    required this.overallRisk,
    required this.implicatedSystems,
    required this.summary,
  });
}

/// A red flag that was triggered.
class RedFlagMatch {
  final RedFlagRule rule;
  final List<String> matchedRequired;
  final List<String> matchedSupporting;

  RedFlagMatch({
    required this.rule,
    required this.matchedRequired,
    required this.matchedSupporting,
  });
}

/// A scored disease candidate.
class CandidateCondition {
  final DiseaseProfile profile;
  final double score; // 0.0 - 1.0
  final double confidence; // How confident we are (based on symptom coverage)
  final ClinicalRisk risk;
  final List<String> matchedCardinal;
  final List<String> matchedCommon;
  final List<String> matchedOccasional;
  final List<String> missingCardinal;
  final String reasoning; // Human-readable explanation of why this was scored

  CandidateCondition({
    required this.profile,
    required this.score,
    required this.confidence,
    required this.risk,
    required this.matchedCardinal,
    required this.matchedCommon,
    required this.matchedOccasional,
    required this.missingCardinal,
    required this.reasoning,
  });
}

/// Main diagnostic engine.
class ClinicalEngine {
  /// Run the full diagnostic pipeline.
  ///
  /// [rawSymptoms]: List of symptom strings as entered/spoken by user.
  /// [patientAge]: Age in years, or null if unknown.
  /// [patientSex]: 'M' or 'F', or null if unknown.
  /// [vitals]: Optional vitals map (e.g., {'bp_systolic': 180, 'temperature': 103}).
  /// [mlConfidences]: Optional map of disease_id → confidence from TFLite model.
  DiagnosticResult diagnose({
    required List<String> rawSymptoms,
    int? patientAge,
    String? patientSex,
    Map<String, double>? vitals,
    Map<String, double>? mlConfidences,
  }) {
    // ── Step 1: Normalize symptoms ──
    final symptoms = _normalizeSymptoms(rawSymptoms);

    // Inject vitals-derived symptoms
    _injectVitalSymptoms(symptoms, vitals);

    // Expand fever variants so scoring works across fever/high_fever/mild_fever.
    // A patient reporting "fever" should partially match diseases expecting
    // "high_fever" or "mild_fever". We do NOT auto-promote fever → high_fever;
    // that requires vitals evidence (handled in _injectVitalSymptoms).
    //
    // CRITICAL: when `high_fever` is explicitly reported (chip or temp ≥104°F),
    // do NOT also inject `mild_fever`. The previous unconditional addAll let
    // a febrile child score partial-credit on every mild-illness profile
    // (common_cold, acute_sinusitis, bronchitis, dental_caries), diluting the
    // ranking at exactly the time a severe differential should dominate.
    final hasHighFever = symptoms.contains('high_fever');
    final hasAnyFever = hasHighFever ||
        symptoms.contains('fever') ||
        symptoms.contains('mild_fever');
    if (hasAnyFever) {
      symptoms.add('fever');
    }
    if (hasAnyFever && !hasHighFever) {
      symptoms.add('mild_fever');
    }

    // Expand runny_nose / rhinorrhea equivalence.
    if (symptoms.contains('runny_nose')) symptoms.add('rhinorrhea');
    if (symptoms.contains('rhinorrhea')) symptoms.add('runny_nose');

    if (symptoms.isEmpty) {
      return DiagnosticResult(
        conditions: [],
        overallRisk: ClinicalRisk.normal,
        implicatedSystems: [],
        summary: 'No symptoms provided. Please enter patient symptoms.',
      );
    }

    // ── Step 2: Check red flags ──
    final redFlag = _checkRedFlags(symptoms, patientAge, patientSex);

    // ── Step 3: Classify body systems ──
    final systemScores = _classifySystems(symptoms);
    final implicatedSystems = systemScores.entries
        .where((e) => e.value > 0.2)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) =>
          (systemScores[b] ?? 0).compareTo(systemScores[a] ?? 0));

    // ── Step 4: Filter candidates to relevant systems ──
    // Include diseases whose primary or secondary system is implicated.
    // But also always include high-prevalence diseases that share ≥1 symptom
    // (doctor's "common things are common" heuristic).
    final candidates = <DiseaseProfile>[];
    for (final disease in diseaseProfiles) {
      final isSystemMatch = implicatedSystems.contains(disease.primarySystem) ||
          disease.secondarySystems.any((s) => implicatedSystems.contains(s));

      final hasAnySymptomMatch =
          disease.symptomProfile.keys.any((s) => symptoms.contains(s));

      if (isSystemMatch && hasAnySymptomMatch) {
        candidates.add(disease);
      } else if (disease.prevalence >= 0.6 && hasAnySymptomMatch) {
        // High-prevalence diseases get a chance even outside system match
        candidates.add(disease);
      }
    }

    // ── Step 5: Score each candidate ──
    final scored = <CandidateCondition>[];
    for (final disease in candidates) {
      scored.add(_scoreCandidate(
        disease: disease,
        symptoms: symptoms,
        patientAge: patientAge,
        patientSex: patientSex,
        mlConfidence: mlConfidences?[disease.id],
      ));
    }

    // ── Step 6: Sort by score, take top results ──
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Filter out very low scores
    final meaningful =
        scored.where((c) => c.score > 0.05).toList();

    // Take top 3-5 depending on score distribution
    final topN = _selectTopN(meaningful);

    // ── Step 7: Determine overall risk ──
    ClinicalRisk overallRisk;
    if (redFlag != null) {
      overallRisk = redFlag.risk;
    } else if (topN.isNotEmpty) {
      overallRisk = topN.first.risk;
    } else {
      overallRisk = ClinicalRisk.normal;
    }

    // ── Step 8: Generate summary ──
    final summary = _generateSummary(
      redFlag: redFlag,
      conditions: topN,
      overallRisk: overallRisk,
      symptoms: symptoms,
    );

    return DiagnosticResult(
      redFlag: redFlag != null
          ? RedFlagMatch(
              rule: redFlag,
              matchedRequired: redFlag.requiredSymptoms
                  .where((s) => symptoms.contains(s))
                  .toList(),
              matchedSupporting: redFlag.supportingSymptoms
                  .where((s) => symptoms.contains(s))
                  .toList(),
            )
          : null,
      conditions: topN,
      overallRisk: overallRisk,
      implicatedSystems: implicatedSystems,
      summary: summary,
    );
  }

  // ================================================================
  // INTERNAL: Symptom normalization
  // ================================================================

  Set<String> _normalizeSymptoms(List<String> raw) {
    final normalized = <String>{};

    for (var s in raw) {
      // Lowercase, trim, replace spaces/hyphens with underscore
      var key = s.toLowerCase().trim().replaceAll(RegExp(r'[\s\-]+'), '_');

      // Remove common noise words
      key = key
          .replaceAll('i_have_', '')
          .replaceAll('having_', '')
          .replaceAll('feeling_', '')
          .replaceAll('patient_has_', '')
          .replaceAll('suffers_from_', '');

      // Check alias map (with chain resolution: alias may point to another alias)
      if (symptomAliases.containsKey(key)) {
        normalized.add(_resolveAliasChain(key));
      } else if (symptomSystemMap.containsKey(key)) {
        // Direct match to known symptom
        normalized.add(key);
      } else {
        // Try partial match — find closest known symptom
        final match = _fuzzyMatchSymptom(key);
        if (match != null) {
          normalized.add(match);
        }
        // If no match, DROP the token. Previously we kept unknown keys in
        // hopes a DiseaseProfile's symptomProfile would have the raw key,
        // but profiles MUST use canonical symptomSystemMap keys (CLAUDE.md
        // rule), so unknowns were pure noise — they inflated `totalMatched`
        // counts nowhere and occasionally leaked into reasoning strings.
      }
    }

    // Auto-promote: if 'fever' and vitals show temp ≥ 102, also add 'high_fever'
    // (handled in _injectVitalSymptoms)

    return normalized;
  }

  /// Follow an alias chain until it reaches either a symptomSystemMap key or
  /// a terminal (non-alias) string. Guards against cycles.
  /// Example: "सांस फूलना" → "breathlessness" → "shortness_of_breath".
  String _resolveAliasChain(String key) {
    String current = key;
    final seen = <String>{};
    while (symptomAliases.containsKey(current) && !seen.contains(current)) {
      seen.add(current);
      final next = symptomAliases[current]!;
      if (next == current) break; // self-reference terminates
      current = next;
    }
    return current;
  }

  String? _fuzzyMatchSymptom(String input) {
    // Substring matching against known symptoms. Requires input length ≥ 5
    // to avoid spurious matches. At length 4, a token like "pain" bound to
    // whichever *_pain SSM key iterated first (36 candidates in the map —
    // non-deterministic). Raising the floor from 4 to 5 matches the Latin
    // threshold in `fuzzy_symptom_matcher.dart` and eliminates the worst
    // ambiguity cases. Native-script (hi/ta/bn/…) phrases route through
    // symptomAliases before they ever reach this path.
    if (input.length < 5) return null;

    final allKnown = <String>{
      ...symptomSystemMap.keys,
      ...symptomAliases.keys,
    };

    // Ambiguity guard: if the input substring-contains (or is contained by)
    // MULTIPLE known SSM / alias keys, we can't deterministically pick one —
    // return null and let the token be dropped. Previously the first match
    // in iteration order won, which made "pain" → "abdominal_pain" silently
    // correct some of the time and wrong others. Ambiguous-drop is honest.
    String? firstMatch;
    int matchCount = 0;
    for (final known in allKnown) {
      if (known.length < 5) continue;
      if (known.contains(input) || input.contains(known)) {
        firstMatch ??= symptomAliases[known] ?? known;
        matchCount++;
        if (matchCount > 1) return null;
      }
    }
    return firstMatch;
  }

  void _injectVitalSymptoms(Set<String> symptoms, Map<String, double>? vitals) {
    if (vitals == null) return;

    final temp = vitals['temperature'] ?? vitals['temp'];
    if (temp != null) {
      if (temp >= 104) {
        symptoms.add('high_fever');
        symptoms.add('fever');
      } else if (temp >= 100.4) {
        symptoms.add('fever');
        if (temp < 102) symptoms.add('mild_fever');
      }
    }

    final bpSys = vitals['bp_systolic'] ?? vitals['systolic'];
    if (bpSys != null && bpSys >= 140) {
      symptoms.add('high_blood_pressure');
      if (bpSys >= 180) {
        // Hypertensive crisis
        symptoms.add('hypertensive_crisis');
      }
    }

    final spo2 = vitals['spo2'] ?? vitals['oxygen'];
    if (spo2 != null && spo2 < 92) {
      symptoms.add('severe_shortness_of_breath');
      symptoms.add('cyanosis');
    } else if (spo2 != null && spo2 < 95) {
      symptoms.add('shortness_of_breath');
    }

    final pulse = vitals['pulse'] ?? vitals['heart_rate'];
    if (pulse != null && pulse > 120) {
      symptoms.add('palpitations');
    }
  }

  // ================================================================
  // INTERNAL: Red flag check
  // ================================================================

  RedFlagRule? _checkRedFlags(
      Set<String> symptoms, int? age, String? sex) {
    RedFlagRule? bestMatch;
    int bestStrength = -1;

    for (final rule in redFlagRules) {
      // Check demographics filter
      if (rule.demographics != null) {
        final demoScore = rule.demographics!.matchScore(age, sex);
        if (demoScore < 0.3) continue; // Demographics don't match
      }

      // ALL required symptoms must be present
      final allRequired =
          rule.requiredSymptoms.every((s) => symptoms.contains(s));
      if (!allRequired) continue;

      // Count supporting matches
      final supportingMatches =
          rule.supportingSymptoms.where((s) => symptoms.contains(s)).length;

      if (supportingMatches >= rule.minSupportingNeeded) {
        // This rule fires. Track the strongest match.
        final strength =
            rule.requiredSymptoms.length + supportingMatches;
        if (strength > bestStrength) {
          bestStrength = strength;
          bestMatch = rule;
        }
      }
    }

    return bestMatch;
  }

  // ================================================================
  // INTERNAL: Body system classification
  // ================================================================

  Map<BodySystem, double> _classifySystems(Set<String> symptoms) {
    final scores = <BodySystem, double>{};

    for (final symptom in symptoms) {
      final mapping = symptomSystemMap[symptom];
      if (mapping == null) continue;

      for (final entry in mapping.entries) {
        scores[entry.key] = (scores[entry.key] ?? 0) + entry.value;
      }
    }

    // Normalize to 0-1 range
    if (scores.isNotEmpty) {
      final maxScore = scores.values.reduce((a, b) => a > b ? a : b);
      if (maxScore > 0) {
        for (final key in scores.keys.toList()) {
          scores[key] = scores[key]! / maxScore;
        }
      }
    }

    return scores;
  }

  // ================================================================
  // INTERNAL: Disease candidate scoring — the core clinical logic
  // ================================================================

  CandidateCondition _scoreCandidate({
    required DiseaseProfile disease,
    required Set<String> symptoms,
    int? patientAge,
    String? patientSex,
    double? mlConfidence,
  }) {
    final matchedCardinal = <String>[];
    final matchedCommon = <String>[];
    final matchedOccasional = <String>[];
    final missingCardinal = <String>[];

    int totalCardinal = 0;

    // Categorize matches
    for (final entry in disease.symptomProfile.entries) {
      final symptomKey = entry.key;
      final role = entry.value;
      final isPresent = symptoms.contains(symptomKey);

      switch (role) {
        case SymptomRole.cardinal:
          totalCardinal++;
          if (isPresent) {
            matchedCardinal.add(symptomKey);
          } else {
            missingCardinal.add(symptomKey);
          }
          break;
        case SymptomRole.common:
          if (isPresent) matchedCommon.add(symptomKey);
          break;
        case SymptomRole.occasional:
          if (isPresent) matchedOccasional.add(symptomKey);
          break;
      }
    }

    // ── Score calculation ──
    // This mirrors how a doctor thinks:
    // "How well does this patient's presentation match what I'd expect?"

    double score = 0.0;

    // A) Cardinal symptom coverage — the most important factor
    // If a disease has 3 cardinal symptoms and patient has all 3, that's very strong.
    // If patient has 0 of 3, this disease is unlikely.
    double cardinalCoverage = totalCardinal > 0
        ? matchedCardinal.length / totalCardinal
        : 0.5; // No cardinals defined → neutral

    // Cardinal coverage is weighted quadratically:
    // Having 3/3 cardinal = 1.0, 2/3 = 0.44, 1/3 = 0.11, 0/3 = 0.0
    // This means missing even ONE cardinal symptom hurts significantly.
    double cardinalScore = cardinalCoverage * cardinalCoverage;
    score += cardinalScore * 0.50; // 50% of total weight

    // B) Common symptom support
    int totalCommon = disease.symptomProfile.values
        .where((r) => r == SymptomRole.common)
        .length;
    double commonCoverage =
        totalCommon > 0 ? matchedCommon.length / totalCommon : 0.0;
    score += commonCoverage * 0.20; // 20% weight

    // C) Occasional symptom bonus (small)
    int totalOccasional = disease.symptomProfile.values
        .where((r) => r == SymptomRole.occasional)
        .length;
    double occasionalCoverage =
        totalOccasional > 0 ? matchedOccasional.length / totalOccasional : 0.0;
    score += occasionalCoverage * 0.05; // 5% weight

    // D) Prevalence prior — "common things are common"
    // GATED on actual match. Previously this added `prevalence * 0.15`
    // unconditionally, so a rare-but-present occasional-symptom hit on a
    // 1.0-prevalence profile (e.g. `fatigue` alone → anemia) could land the
    // score at 0.15+ and rank above more specific differentials. Now the
    // prevalence floor only applies when the patient presents with at least
    // one cardinal or common symptom of the disease.
    if (matchedCardinal.isNotEmpty || matchedCommon.isNotEmpty) {
      score += disease.prevalence * 0.15; // 15% weight
    }

    // E) Specificity bonus — if the patient's symptoms are mostly explained
    // by this disease, that's better than a disease that only explains 1 symptom.
    int totalMatched =
        matchedCardinal.length + matchedCommon.length + matchedOccasional.length;
    double explanationRatio =
        symptoms.isNotEmpty ? totalMatched / symptoms.length : 0.0;
    // Cap at 1.0 (a disease can't explain more symptoms than exist)
    explanationRatio = explanationRatio.clamp(0.0, 1.0);
    score += explanationRatio * 0.10; // 10% weight

    // ── Penalties ──

    // Missing cardinal penalty: each missing cardinal is a strong negative signal.
    // But context matters: missing 1 of 3 cardinals is less bad than missing 1 of 1.
    if (totalCardinal > 0 && missingCardinal.isNotEmpty) {
      double matchedRatio = matchedCardinal.length / totalCardinal;
      // Penalty scales with how many cardinals are missing.
      // pow(ratio, 1.5): missing 1/2 = 0.35, missing 1/3 = 0.54, missing 1/4 = 0.65
      // missing 3/4 = 0.09, missing all = 0.0
      // This is gentler than quadratic but still punishes heavily for mostly-missing.
      double penalty = matchedRatio;
      if (matchedRatio > 0 && matchedRatio < 1) {
        // Use pow 1.5 for balanced penalty
        penalty = matchedRatio * (0.5 + 0.5 * matchedRatio);
      }
      score *= penalty;
    }

    // If NO symptoms at all matched, this disease shouldn't appear
    if (totalMatched == 0) {
      score = 0.0;
    }

    // CRITICAL: If disease has cardinal symptoms but NONE matched,
    // eliminate it. A doctor never considers a diagnosis where
    // none of the defining features are present.
    if (totalCardinal > 0 && matchedCardinal.isEmpty) {
      score = 0.0;
    }

    // ── Demographic adjustment ──
    double demoMultiplier = disease.demographics.matchScore(patientAge, patientSex);
    score *= demoMultiplier;

    // ── ML confidence integration (optional boost) ──
    // ML acts as a tiebreaker / confidence boost, not the primary signal.
    // The underlying MLP-vs-RF agreement on held-out data is ~0.55, so the ML
    // signal is noisy. Cap the max boost at 1.25× (mlConfidence=1.0) instead
    // of 1.5× — this keeps ML as a tiebreaker without letting it flip a
    // better-reasoned clinical ranking on a single confident logit.
    //
    // Clamp mlConfidence to [0, 1] before use. Incoming confidences from
    // `MLService._getMLConfidences` are already softmax probabilities so
    // should never exceed 1.0, but defensive clamping also floors accidental
    // negatives (which would DEFLATE the score) at 0 without special-casing.
    if (mlConfidence != null) {
      final clamped = mlConfidence.clamp(0.0, 1.0);
      if (clamped > 0.1) {
        double mlBoost = 1.0 + (clamped * 0.25);
        score *= mlBoost;
      }
    }

    // Clamp final score
    score = score.clamp(0.0, 1.0);

    // ── Confidence estimate ──
    // How sure are we about this diagnosis?
    double confidence;
    if (totalCardinal > 0 && matchedCardinal.length == totalCardinal) {
      // All cardinal symptoms present
      confidence = 0.7 + (commonCoverage * 0.2) + (occasionalCoverage * 0.1);
    } else if (totalCardinal > 0 && matchedCardinal.isNotEmpty) {
      confidence = 0.3 + (cardinalCoverage * 0.4);
    } else {
      confidence = 0.1 + (commonCoverage * 0.3);
    }
    confidence = confidence.clamp(0.0, 1.0);

    // ── Risk level for this candidate ──
    ClinicalRisk risk = _adjustRisk(
      disease.typicalRisk,
      cardinalCoverage,
      totalMatched,
      patientAge,
    );

    // ── Build reasoning string ──
    final reasoning = _buildReasoning(
      disease: disease,
      matchedCardinal: matchedCardinal,
      matchedCommon: matchedCommon,
      missingCardinal: missingCardinal,
      cardinalCoverage: cardinalCoverage,
    );

    return CandidateCondition(
      profile: disease,
      score: score,
      confidence: confidence,
      risk: risk,
      matchedCardinal: matchedCardinal,
      matchedCommon: matchedCommon,
      matchedOccasional: matchedOccasional,
      missingCardinal: missingCardinal,
      reasoning: reasoning,
    );
  }

  ClinicalRisk _adjustRisk(
    ClinicalRisk baseRisk,
    double cardinalCoverage,
    int totalMatched,
    int? age,
  ) {
    // Don't upgrade risk beyond base unless high confidence
    // But DO upgrade if patient is vulnerable (very young, very old)
    ClinicalRisk risk = baseRisk;

    // Age-based escalation. Very young children and the elderly decompensate
    // fast, so we upgrade risk more aggressively for them. Previous threshold
    // of `cardinalCoverage > 0.6` left a dangerous gap: a feverish <5yo with
    // poor perfusion and tachycardia would score ~0.3 cardinal coverage on
    // the curated profiles (no dedicated sepsis profile exists), bypass the
    // 11 red-flag rules because none of them require exactly
    // "fever + poor perfusion", and land in "moderate" instead of "urgent"
    // — a septic child would look like a casual visit to an ASHA.
    //
    // Lowering to 0.3 closes that gap while still requiring at least one
    // cardinal-level symptom to match. Normal→moderate unconditional upgrade
    // is unchanged.
    if (age != null && (age < 5 || age > 65)) {
      if (risk == ClinicalRisk.normal) risk = ClinicalRisk.moderate;
      // Threshold tightened 0.3 → 0.25 so a single cardinal match on a
      // 4-cardinal profile (0.25 exactly) still escalates for vulnerable
      // ages. On a 4-cardinal febrile profile, one matched cardinal lands
      // at 0.25 which was previously JUST below the gate.
      if (risk == ClinicalRisk.moderate && cardinalCoverage >= 0.25) {
        risk = ClinicalRisk.urgent;
      }
    }

    // If very few symptoms match, don't assign high risk
    if (totalMatched <= 1 && risk == ClinicalRisk.urgent) {
      risk = ClinicalRisk.moderate;
    }

    return risk;
  }

  String _buildReasoning({
    required DiseaseProfile disease,
    required List<String> matchedCardinal,
    required List<String> matchedCommon,
    required List<String> missingCardinal,
    required double cardinalCoverage,
  }) {
    final parts = <String>[];

    if (matchedCardinal.isNotEmpty) {
      final formatted = matchedCardinal.map(_humanize).join(', ');
      parts.add(
          'Key symptoms present: $formatted (${matchedCardinal.length}/${disease.cardinalCount} cardinal)');
    }

    if (matchedCommon.isNotEmpty) {
      final formatted = matchedCommon.map(_humanize).join(', ');
      parts.add('Supporting symptoms: $formatted');
    }

    if (missingCardinal.isNotEmpty) {
      final formatted = missingCardinal.map(_humanize).join(', ');
      parts.add('NOTE: Expected but not reported: $formatted');
    }

    if (cardinalCoverage == 1.0 && disease.cardinalCount > 1) {
      parts.add('All cardinal symptoms present — strong match');
    }

    return parts.join('. ');
  }

  String _humanize(String key) {
    return key.replaceAll('_', ' ');
  }

  // ================================================================
  // INTERNAL: Select top N results
  // ================================================================

  List<CandidateCondition> _selectTopN(List<CandidateCondition> scored) {
    if (scored.isEmpty) return [];
    if (scored.length <= 3) return scored;

    // Always include top 3
    final result = scored.take(3).toList();

    // Include 4th/5th if their score is within 50% of top score
    final topScore = scored.first.score;
    for (int i = 3; i < scored.length && i < 5; i++) {
      if (scored[i].score >= topScore * 0.5) {
        result.add(scored[i]);
      }
    }

    return result;
  }

  // ================================================================
  // INTERNAL: Generate human-readable summary
  // ================================================================

  String _generateSummary({
    RedFlagRule? redFlag,
    required List<CandidateCondition> conditions,
    required ClinicalRisk overallRisk,
    required Set<String> symptoms,
  }) {
    final parts = <String>[];

    if (redFlag != null) {
      parts.add('⚠️ RED FLAG: ${redFlag.conditionName}');
      parts.add(redFlag.immediateAction);
      parts.add('');
    }

    if (conditions.isNotEmpty) {
      parts.add('Based on the reported symptoms (${symptoms.map(_humanize).join(", ")}):');
      parts.add('');

      for (int i = 0; i < conditions.length; i++) {
        final c = conditions[i];
        final pct = (c.confidence * 100).round();
        parts.add(
            '${i + 1}. ${c.profile.displayName} — $pct% confidence');
        parts.add('   ${c.profile.description}');
        if (c.missingCardinal.isNotEmpty) {
          parts.add(
              '   ⚡ Ask about: ${c.missingCardinal.map(_humanize).join(", ")}');
        }
      }
    } else {
      parts.add(
          'Unable to determine specific condition from reported symptoms.');
      parts.add('Consider referring to a doctor for examination.');
    }

    return parts.join('\n');
  }
}

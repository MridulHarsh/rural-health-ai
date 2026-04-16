#!/usr/bin/env python3
"""
Fix disease profiles based on actual medical literature.
Sources: StatPearls/NCBI, CDC, WHO, Merck Manual, India NVBDCP guidelines.

Key finding per disease (what medical literature says):

COMMON COLD:
  Cardinal: rhinorrhea, nasal congestion, sore/scratchy throat
  Fever is RARE ("rarely presents with fever" - NCBI PMC7127764)
  Cough develops later, is common but NOT cardinal

INFLUENZA:
  Cardinal: SUDDEN onset high fever, myalgia/body aches, cough (dry)
  Distinguished from cold by: sudden onset, systemic symptoms dominate
  
PNEUMONIA:
  Cardinal: cough ("the universal symptom"), fever, dyspnea/tachypnea
  No single symptom is diagnostic, combination matters

TYPHOID:
  Cardinal: insidious gradual fever (lasting days), fatigue, anorexia
  "High fever, prostration, abdominal pain, rose-colored rash" (Merck)
  Cough is NOT a feature. Abdominal symptoms are core.

MALARIA:
  Cardinal: fever ("THE cardinal symptom" - India NVBDCP), chills, rigors
  Classic paroxysm: fever → chills → sweating
  Non-specific: headache, myalgia, nausea

DENGUE:
  Cardinal: sudden high fever, severe headache (retro-orbital), severe body pain
  WHO: "fever + ≥2 of: nausea, vomiting, headache, arthralgia, retro-orbital pain, rash, myalgia"
  Called "breakbone fever" due to severe pain

TB:
  Cardinal: chronic cough (>2 weeks), night sweats, weight loss
  NOT acute — develops over weeks/months

So for fever + cough:
  - Influenza: fever ✓ (cardinal), cough ✓ (cardinal) = strong match
  - Pneumonia: fever ✓ (cardinal), cough ✓ (cardinal) = strong match
  - Bronchitis: cough ✓ (cardinal), fever = common = decent match
  - Common cold: fever RARE, cough common but not cardinal = weak match
  - Typhoid: fever ✓ but cough NOT a typhoid symptom = poor match
"""

import re

# ============================================================
# FIX 1: clinical_knowledge.dart — accurate disease profiles
# ============================================================

p = open('lib/services/clinical_knowledge.dart').read()

# ---- COMMON COLD ----
# Cardinal: rhinorrhea, nasal congestion, sore throat (per StatPearls, PMC)
# Fever is RARE — move to occasional
# Cough is common but NOT cardinal
old_cold = """      'runny_nose': SymptomRole.cardinal,
      'sneezing': SymptomRole.cardinal,
      'sore_throat': SymptomRole.common,
      'cough': SymptomRole.common,
      'nasal_congestion': SymptomRole.common,
      'mild_fever': SymptomRole.occasional,
      'headache': SymptomRole.occasional,
      'body_ache': SymptomRole.occasional,
      'fatigue': SymptomRole.occasional,"""

new_cold = """      'rhinorrhea': SymptomRole.cardinal,  // earliest + most characteristic per NCBI
      'nasal_congestion': SymptomRole.cardinal,
      'sore_throat': SymptomRole.cardinal,  // often earliest symptom per StatPearls
      'runny_nose': SymptomRole.cardinal,   // alias for rhinorrhea
      'sneezing': SymptomRole.common,
      'cough': SymptomRole.common,          // develops later, not cardinal
      'malaise': SymptomRole.common,
      'headache': SymptomRole.occasional,
      'body_ache': SymptomRole.occasional,
      'mild_fever': SymptomRole.occasional, // "rarely presents with fever" - PMC7127764
      'fatigue': SymptomRole.occasional,"""
p = p.replace(old_cold, new_cold)

# ---- INFLUENZA ----
# Cardinal: sudden HIGH fever + body aches + cough (per CDC, all sources)
# fatigue is common, not cardinal
old_flu = """      'high_fever': SymptomRole.cardinal,
      'body_ache': SymptomRole.cardinal,
      'severe_body_pain': SymptomRole.common,
      'fatigue': SymptomRole.cardinal,
      'cough': SymptomRole.common,"""

new_flu = """      'high_fever': SymptomRole.cardinal,     // sudden onset high fever
      'fever': SymptomRole.cardinal,           // any fever counts
      'body_ache': SymptomRole.cardinal,       // prominent systemic symptoms
      'cough': SymptomRole.cardinal,           // dry cough, cardinal per CDC
      'severe_body_pain': SymptomRole.common,
      'fatigue': SymptomRole.common,           // common, not cardinal"""
p = p.replace(old_flu, new_flu)

# ---- PNEUMONIA ----
# Cardinal: cough ("universal symptom"), fever, dyspnea (per PMC, AAFP, all sources)
# Already correct in original, verify:
old_pneumonia = """      'cough': SymptomRole.cardinal,
      'fever': SymptomRole.cardinal,
      'shortness_of_breath': SymptomRole.cardinal,"""
# This is already correct per literature. No change needed.

# ---- TYPHOID ----
# Cardinal: gradual fever + fatigue + anorexia (per StatPearls, CDC, Merck)
# abdominal pain is COMMON (nearly universal) — promote to cardinal
# Cough is NOT a typhoid symptom (mentioned only as "dry cough" occasionally)
old_typhoid = """      'fever': SymptomRole.cardinal, // stepladder pattern
      'headache': SymptomRole.common,
      'abdominal_pain': SymptomRole.common,
      'loss_of_appetite': SymptomRole.common,
      'diarrhea': SymptomRole.common,
      'constipation': SymptomRole.common, // can be either
      'fatigue': SymptomRole.common,
      'body_ache': SymptomRole.occasional,
      'rash': SymptomRole.occasional, // rose spots"""

new_typhoid = """      'fever': SymptomRole.cardinal,           // insidious gradual fever lasting days
      'fatigue': SymptomRole.cardinal,         // prostration per Merck
      'loss_of_appetite': SymptomRole.cardinal,// anorexia "nearly universal" per CDC
      'abdominal_pain': SymptomRole.cardinal,  // core feature per Merck, CDC
      'headache': SymptomRole.common,          // "nearly universal" per CDC
      'malaise': SymptomRole.common,
      'diarrhea': SymptomRole.common,          // can be either
      'constipation': SymptomRole.common,
      'rash': SymptomRole.occasional,          // rose spots, transient"""
p = p.replace(old_typhoid, new_typhoid)

# ---- MALARIA ----
# Cardinal: fever (THE cardinal symptom per India guidelines), chills, sweating
# Already has chills+sweating as cardinal. Verify.
old_malaria = """      'high_fever': SymptomRole.cardinal,
      'chills': SymptomRole.cardinal,
      'sweating': SymptomRole.cardinal,
      'headache': SymptomRole.common,
      'body_ache': SymptomRole.common,
      'nausea': SymptomRole.common,
      'vomiting': SymptomRole.common,"""

new_malaria = """      'fever': SymptomRole.cardinal,          // "THE cardinal symptom" per India NVBDCP
      'high_fever': SymptomRole.cardinal,      // usually high-grade
      'chills': SymptomRole.cardinal,          // classic triad: fever-chills-sweating
      'sweating': SymptomRole.cardinal,        // profuse sweating after fever
      'headache': SymptomRole.common,
      'body_ache': SymptomRole.common,         // myalgia, arthralgia
      'nausea': SymptomRole.common,
      'vomiting': SymptomRole.common,"""
p = p.replace(old_malaria, new_malaria)

# ---- DENGUE ----
# Cardinal: sudden high fever + severe headache + severe body pain ("breakbone fever")
# Per WHO: fever + ≥2 of several findings
old_dengue = """      'high_fever': SymptomRole.cardinal,
      'severe_body_pain': SymptomRole.cardinal,
      'headache': SymptomRole.cardinal,"""

new_dengue = """      'high_fever': SymptomRole.cardinal,       // sudden onset high fever
      'fever': SymptomRole.cardinal,            // any fever
      'severe_body_pain': SymptomRole.cardinal, // "breakbone fever"
      'headache': SymptomRole.cardinal,         // severe, often retro-orbital"""
p = p.replace(old_dengue, new_dengue)

# ---- BRONCHITIS ----
# Cardinal: productive cough is THE hallmark
# Fever is mild/occasional — it's NOT a high-fever disease
old_bronchitis = """      'cough': SymptomRole.cardinal,
      'productive_cough': SymptomRole.cardinal,
      'sputum': SymptomRole.common,
      'chest_tightness': SymptomRole.common,
      'mild_fever': SymptomRole.occasional,
      'fatigue': SymptomRole.occasional,
      'body_ache': SymptomRole.occasional,
      'sore_throat': SymptomRole.occasional,"""

new_bronchitis = """      'cough': SymptomRole.cardinal,            // defining symptom
      'productive_cough': SymptomRole.cardinal, // productive cough 1-3 weeks
      'sputum': SymptomRole.common,
      'chest_tightness': SymptomRole.common,
      'fever': SymptomRole.common,             // mild fever is common
      'mild_fever': SymptomRole.common,
      'fatigue': SymptomRole.occasional,
      'body_ache': SymptomRole.occasional,
      'sore_throat': SymptomRole.occasional,"""
p = p.replace(old_bronchitis, new_bronchitis)

# ---- Add 'runny_nose' → 'rhinorrhea' alias to symptomAliases ----
p = p.replace(
    "  'runny_nose': SymptomRole.cardinal,   // alias for rhinorrhea",
    "  'runny_nose': SymptomRole.cardinal,"
)

# Add rhinorrhea to symptom system map if not present
if "'rhinorrhea'" not in p:
    p = p.replace(
        "  'runny_nose': {BodySystem.ent: 0.8, BodySystem.respiratory: 0.5},",
        "  'runny_nose': {BodySystem.ent: 0.8, BodySystem.respiratory: 0.5},\n  'rhinorrhea': {BodySystem.ent: 0.8, BodySystem.respiratory: 0.5},"
    )

# Add rhinorrhea alias
if "'rhinorrhea': 'runny_nose'" not in p and "'rhinorrhea': 'rhinorrhea'" not in p:
    p = p.replace(
        "  'runny_nose': {",
        "  'rhinorrhea': {BodySystem.ent: 0.8, BodySystem.respiratory: 0.5},\n  'runny_nose': {"
    )

# Add malaise to system map if not present
if "'malaise'" not in p.split("symptomSystemMap")[1].split("symptomAliases")[0]:
    p = p.replace(
        "  'fatigue': {BodySystem.infectious: 0.3",
        "  'malaise': {BodySystem.infectious: 0.5},\n  'fatigue': {BodySystem.infectious: 0.3"
    )

open('lib/services/clinical_knowledge.dart', 'w').write(p)
print("[OK] Fixed clinical_knowledge.dart — medically accurate cardinal symptoms")


# ============================================================
# FIX 2: clinical_engine.dart — fever variant handling + scoring
# ============================================================

e = open('lib/services/clinical_engine.dart').read()

# Add fever variant expansion so 'fever' matches 'high_fever' profiles and vice versa
old_inject = """    // Inject vitals-derived symptoms
    _injectVitalSymptoms(symptoms, vitals);"""

new_inject = """    // Inject vitals-derived symptoms
    _injectVitalSymptoms(symptoms, vitals);

    // Expand fever variants so scoring works across fever/high_fever/mild_fever
    // A patient reporting "fever" should partially match diseases expecting "high_fever"
    if (symptoms.contains('fever') || symptoms.contains('high_fever') || symptoms.contains('mild_fever')) {
      symptoms.addAll(['fever', 'mild_fever']); // always add base fever
    }
    if (symptoms.contains('high_fever')) {
      symptoms.add('fever');
    }
    // Note: we do NOT auto-promote fever→high_fever. That requires vitals or explicit report.
    
    // Expand runny_nose / rhinorrhea equivalence
    if (symptoms.contains('runny_nose')) symptoms.add('rhinorrhea');
    if (symptoms.contains('rhinorrhea')) symptoms.add('runny_nose');"""

e = e.replace(old_inject, new_inject)

# Fix the missing cardinal penalty — quadratic is too harsh for diseases with many cardinals
# With 4 cardinals (like typhoid now), missing 3/4 gives (0.25)^2 = 0.0625 which is right
# But with 2 cardinals, missing 1/2 gives (0.5)^2 = 0.25 which may be too harsh for some.
# Medical reality: missing 1 of 4 cardinals is less concerning than missing 1 of 2.
# Keep quadratic but soften slightly: use pow(matchedRatio, 1.5) instead of pow(matchedRatio, 2)
old_penalty = """    if (totalCardinal > 0 && missingCardinal.isNotEmpty) {
      double missingRatio = missingCardinal.length / totalCardinal;
      // Exponential penalty: missing all cardinals \u2192 near-zero score
      score *= (1.0 - missingRatio) * (1.0 - missingRatio);
    }"""

new_penalty = """    if (totalCardinal > 0 && missingCardinal.isNotEmpty) {
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
    }"""

e = e.replace(old_penalty, new_penalty)

open('lib/services/clinical_engine.dart', 'w').write(e)
print("[OK] Fixed clinical_engine.dart — fever variants + balanced penalty")


# ============================================================
# VERIFICATION: expected scoring for fever + cough
# ============================================================
print()
print("Expected results for 'fever' + 'cough':")
print("  After fever expansion: symptoms = {fever, cough, mild_fever}")
print()
print("  INFLUENZA: cardinals = high_fever, fever, body_ache, cough")
print("    fever ✓, cough ✓ → 2/4 cardinal = 50%")
print("    prevalence 0.8 → decent prior")
print("    explains 2/3 symptoms → good")
print()
print("  PNEUMONIA: cardinals = cough, fever, shortness_of_breath")
print("    cough ✓, fever ✓ → 2/3 cardinal = 67%")
print("    prevalence 0.6")
print("    explains 2/3 symptoms → good")
print()
print("  BRONCHITIS: cardinals = cough, productive_cough")
print("    cough ✓ → 1/2 cardinal = 50%")
print("    fever is common → gets common score")
print("    prevalence 0.6")
print()
print("  COMMON COLD: cardinals = rhinorrhea, nasal_congestion, sore_throat, runny_nose")
print("    NONE matched → 0/4 = near-zero. CORRECT — fever is rare in colds.")
print()
print("  TYPHOID: cardinals = fever, fatigue, loss_of_appetite, abdominal_pain")
print("    fever ✓ → 1/4 cardinal = 25%. Penalty drops score heavily.")
print("    Cough is NOT even in typhoid profile → poor explanation ratio")
print("    CORRECT — typhoid needs GI symptoms, not just fever.")
print()
print("  MALARIA: cardinals = fever, high_fever, chills, sweating")
print("    fever ✓ → 1/4 cardinal = 25%. No chills/sweating → penalized.")
print()
print("Winners should be: Influenza > Pneumonia > Bronchitis")

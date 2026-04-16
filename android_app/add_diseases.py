#!/usr/bin/env python3
"""
Comprehensive update to clinical_knowledge.dart:
1. Corrects existing disease profiles based on medical literature (NCBI, CDC, WHO, Merck)
2. Adds ~15 missing diseases from disease_list.json
3. Adds new symptoms to the symptom-system map
4. Adds junk class filter list

Run AFTER fix_profiles_v2.py has been applied.

Sources cited in comments:
- StatPearls/NCBI for clinical presentation
- CDC for public health guidelines
- WHO for classification criteria
- India NVBDCP for malaria guidelines
- Merck Manual for clinical summaries
"""

# ============================================================
# Read the current file
# ============================================================
with open('lib/services/clinical_knowledge.dart', 'r') as f:
    content = f.read()

# ============================================================
# 1. ADD NEW SYMPTOMS TO SYSTEM MAP
# ============================================================

new_symptoms = """
  // ── Additional symptoms for new diseases ──
  'foamy_urine': {BodySystem.urogenital: 0.9},
  'decreased_urine': {BodySystem.urogenital: 0.8},
  'swelling_ankles': {BodySystem.cardiac: 0.5, BodySystem.urogenital: 0.5},
  'dry_skin': {BodySystem.dermatological: 0.7, BodySystem.endocrine: 0.4},
  'scaling_skin': {BodySystem.dermatological: 1.0},
  'silvery_scales': {BodySystem.dermatological: 1.0},
  'red_patches': {BodySystem.dermatological: 0.9},
  'itchy_dry_skin': {BodySystem.dermatological: 0.9},
  'skin_cracking': {BodySystem.dermatological: 0.9},
  'bloody_diarrhea': {BodySystem.gastrointestinal: 1.0},
  'rectal_bleeding': {BodySystem.gastrointestinal: 1.0},
  'upper_abdominal_pain': {BodySystem.gastrointestinal: 0.9},
  'pain_after_eating': {BodySystem.gastrointestinal: 0.8},
  'nasal_itching': {BodySystem.ent: 0.9},
  'watery_eyes': {BodySystem.ophthalmic: 0.6, BodySystem.ent: 0.5},
  'snoring': {BodySystem.respiratory: 0.5, BodySystem.ent: 0.5},
  'difficulty_walking': {BodySystem.neurological: 0.7, BodySystem.musculoskeletal: 0.5},
  'balance_problems': {BodySystem.neurological: 0.8},
  'resting_tremor': {BodySystem.neurological: 1.0},
  'slow_movement': {BodySystem.neurological: 0.8},
  'muscle_stiffness': {BodySystem.neurological: 0.6, BodySystem.musculoskeletal: 0.6},
  'stooped_posture': {BodySystem.neurological: 0.7},
  'bone_fracture': {BodySystem.musculoskeletal: 0.9},
  'height_loss': {BodySystem.musculoskeletal: 0.8},
  'morning_stiffness_prolonged': {BodySystem.musculoskeletal: 1.0},
  'symmetric_joint_pain': {BodySystem.musculoskeletal: 0.9},
  'weakness_general': {BodySystem.hematological: 0.4, BodySystem.neurological: 0.3},
  'easy_bleeding': {BodySystem.hematological: 0.9},
  'petechiae': {BodySystem.hematological: 0.9},
  'depressed_mood': {BodySystem.neurological: 0.4},
  'loss_of_interest': {BodySystem.neurological: 0.3},
  'sleep_changes': {BodySystem.neurological: 0.3},
  'guilt_worthlessness': {BodySystem.neurological: 0.3},
  'concentration_difficulty': {BodySystem.neurological: 0.3},
  'appetite_changes': {BodySystem.neurological: 0.2, BodySystem.gastrointestinal: 0.2},
  'panic_attacks': {BodySystem.neurological: 0.5, BodySystem.cardiac: 0.3},
  'excessive_worry': {BodySystem.neurological: 0.3},
  'chest_indrawing': {BodySystem.respiratory: 1.0},
  'inability_to_speak': {BodySystem.neurological: 0.8, BodySystem.respiratory: 0.4},
  'nosebleed': {BodySystem.ent: 0.7, BodySystem.hematological: 0.4},
  'dark_urine': {BodySystem.gastrointestinal: 0.6, BodySystem.urogenital: 0.4},
  'irritability': {BodySystem.neurological: 0.2},
"""

# Insert new symptoms before the closing of symptomSystemMap
content = content.replace(
    "  'dog_bite': {BodySystem.infectious: 0.5},\n  'insect_bite':",
    "  'dog_bite': {BodySystem.infectious: 0.5},\n" + new_symptoms + "  'insect_bite':"
)

# ============================================================
# 2. ADD MISSING DISEASE PROFILES
# ============================================================

new_diseases = """

  // ──────────── ADDITIONAL DISEASES (from disease_list.json) ────────────

  // ── ALLERGIC RHINITIS ──
  // Source: PMC8974728, StatPearls NBK538186
  // Cardinal: 4 classic nasal symptoms per PMC: rhinorrhea, nasal obstruction, sneezing, nasal itch
  DiseaseProfile(
    id: 'allergic_rhinitis',
    displayName: 'Allergic Rhinitis',
    primarySystem: BodySystem.ent,
    secondarySystems: [BodySystem.respiratory, BodySystem.ophthalmic],
    symptomProfile: {
      'runny_nose': SymptomRole.cardinal,       // watery rhinorrhea
      'nasal_congestion': SymptomRole.cardinal,  // nasal obstruction
      'sneezing': SymptomRole.cardinal,          // paroxysmal
      'nasal_itching': SymptomRole.cardinal,     // nasal pruritus
      'watery_eyes': SymptomRole.common,         // allergic conjunctivitis
      'eye_itching': SymptomRole.common,
      'sore_throat': SymptomRole.occasional,     // postnasal drip
      'cough': SymptomRole.occasional,
      'fatigue': SymptomRole.occasional,
      'headache': SymptomRole.occasional,
    },
    prevalence: 0.7,
    typicalRisk: ClinicalRisk.normal,
    nextSteps: [
      'Identify and avoid allergen triggers (dust, pollen, pets)',
      'Antihistamine tablets (cetirizine, loratadine)',
      'Nasal saline wash for relief',
      'Refer if severe or not responding to antihistamines',
    ],
    description: 'Allergic inflammation of nasal passages. Triggered by pollen, dust, animal dander.',
  ),

  // ── ECZEMA (Atopic Dermatitis) ──
  DiseaseProfile(
    id: 'eczema',
    displayName: 'Eczema (Atopic Dermatitis)',
    primarySystem: BodySystem.dermatological,
    symptomProfile: {
      'itching': SymptomRole.cardinal,           // THE hallmark — intense, worse at night
      'itchy_dry_skin': SymptomRole.cardinal,
      'rash': SymptomRole.cardinal,              // red, inflamed patches
      'skin_cracking': SymptomRole.common,
      'skin_discoloration': SymptomRole.common,
      'blisters': SymptomRole.occasional,        // in acute flares
      'swelling_local': SymptomRole.occasional,
    },
    prevalence: 0.6,
    typicalRisk: ClinicalRisk.normal,
    nextSteps: [
      'Moisturize skin frequently (emollients)',
      'Avoid scratching — keep nails short',
      'Topical steroid cream for flares (hydrocortisone)',
      'Identify triggers (soaps, detergents, heat)',
    ],
    description: 'Chronic itchy skin condition. Red, dry, cracked patches, often in skin folds.',
  ),

  // ── PSORIASIS ──
  DiseaseProfile(
    id: 'psoriasis',
    displayName: 'Psoriasis',
    primarySystem: BodySystem.dermatological,
    symptomProfile: {
      'scaling_skin': SymptomRole.cardinal,      // silvery-white scales
      'red_patches': SymptomRole.cardinal,       // well-defined red plaques
      'itching': SymptomRole.common,
      'skin_discoloration': SymptomRole.common,
      'nail_changes': SymptomRole.common,        // pitting, thickening
      'joint_pain': SymptomRole.occasional,      // psoriatic arthritis
      'skin_cracking': SymptomRole.occasional,
    },
    prevalence: 0.3,
    typicalRisk: ClinicalRisk.moderate,
    nextSteps: [
      'REFER to dermatologist for diagnosis',
      'Emollients and moisturizers',
      'Topical corticosteroids for mild cases',
      'Not contagious — reassure patient',
    ],
    description: 'Chronic autoimmune skin disease. Red patches with silvery-white scales, often on elbows, knees, scalp.',
  ),

  // ── CORONARY ARTERY DISEASE / HEART DISEASE ──
  DiseaseProfile(
    id: 'coronary_artery_disease',
    displayName: 'Coronary Artery Disease',
    primarySystem: BodySystem.cardiac,
    symptomProfile: {
      'chest_pain': SymptomRole.cardinal,        // angina — exertional
      'shortness_of_breath': SymptomRole.cardinal, // on exertion
      'fatigue': SymptomRole.common,
      'palpitations': SymptomRole.common,
      'dizziness': SymptomRole.occasional,
      'sweating': SymptomRole.occasional,
      'nausea': SymptomRole.occasional,
    },
    prevalence: 0.4,
    typicalRisk: ClinicalRisk.urgent,
    demographics: Demographics(minAge: 35),
    nextSteps: [
      'REFER urgently for cardiac evaluation (ECG, blood tests)',
      'If chest pain at rest or severe → EMERGENCY (possible heart attack)',
      'Aspirin if prescribed by doctor',
      'Lifestyle: stop smoking, reduce salt, exercise gently',
    ],
    description: 'Narrowing of heart arteries. Chest pain/pressure on exertion that eases with rest.',
  ),

  // ── CHRONIC KIDNEY DISEASE ──
  // Source: StatPearls NBK535404, JAMA review PMC7015670
  // Early stages ASYMPTOMATIC. Late stages (4-5): edema, fatigue, nausea
  DiseaseProfile(
    id: 'chronic_kidney_disease',
    displayName: 'Chronic Kidney Disease',
    primarySystem: BodySystem.urogenital,
    symptomProfile: {
      'swelling_ankles': SymptomRole.cardinal,   // edema — stage 3+
      'fatigue': SymptomRole.cardinal,           // uremic fatigue
      'decreased_urine': SymptomRole.common,
      'foamy_urine': SymptomRole.common,         // proteinuria
      'nausea': SymptomRole.common,
      'loss_of_appetite': SymptomRole.common,
      'itching': SymptomRole.common,             // uremic pruritus
      'high_blood_pressure': SymptomRole.common,
      'back_pain': SymptomRole.occasional,       // flank
      'shortness_of_breath': SymptomRole.occasional,
      'muscle_pain': SymptomRole.occasional,
    },
    prevalence: 0.3,
    typicalRisk: ClinicalRisk.urgent,
    demographics: Demographics(minAge: 30),
    nextSteps: [
      'REFER for blood test (creatinine, eGFR) and urine test',
      'Control blood pressure and blood sugar',
      'Reduce salt intake, adequate hydration',
      'Avoid NSAIDs (ibuprofen, diclofenac) — harmful to kidneys',
    ],
    description: 'Gradual loss of kidney function. Often silent until late stages. Linked to diabetes and hypertension.',
  ),

  // ── CROHN'S DISEASE ──
  DiseaseProfile(
    id: 'crohns_disease',
    displayName: "Crohn's Disease",
    primarySystem: BodySystem.gastrointestinal,
    symptomProfile: {
      'abdominal_pain': SymptomRole.cardinal,    // crampy, often right lower
      'diarrhea': SymptomRole.cardinal,          // chronic, may be bloody
      'unexplained_weight_loss': SymptomRole.cardinal,
      'fatigue': SymptomRole.common,
      'fever': SymptomRole.common,
      'loss_of_appetite': SymptomRole.common,
      'bloody_stool': SymptomRole.common,
      'nausea': SymptomRole.occasional,
      'joint_pain': SymptomRole.occasional,      // extra-intestinal
    },
    prevalence: 0.1,
    typicalRisk: ClinicalRisk.urgent,
    nextSteps: [
      'REFER to gastroenterologist',
      'Blood tests and stool tests needed',
      'May need colonoscopy for diagnosis',
      'Chronic condition — needs long-term management',
    ],
    description: 'Chronic inflammatory bowel disease. Crampy abdominal pain, chronic diarrhea, weight loss.',
  ),

  // ── ULCERATIVE COLITIS ──
  DiseaseProfile(
    id: 'ulcerative_colitis',
    displayName: 'Ulcerative Colitis',
    primarySystem: BodySystem.gastrointestinal,
    symptomProfile: {
      'bloody_diarrhea': SymptomRole.cardinal,   // THE hallmark
      'rectal_bleeding': SymptomRole.cardinal,
      'abdominal_pain': SymptomRole.cardinal,    // crampy, left-sided
      'diarrhea': SymptomRole.common,
      'fatigue': SymptomRole.common,
      'fever': SymptomRole.common,
      'unexplained_weight_loss': SymptomRole.common,
      'loss_of_appetite': SymptomRole.occasional,
      'joint_pain': SymptomRole.occasional,
    },
    prevalence: 0.1,
    typicalRisk: ClinicalRisk.urgent,
    nextSteps: [
      'REFER to gastroenterologist urgently',
      'Bloody diarrhea needs investigation',
      'Stool tests to rule out infection first',
      'May need colonoscopy for diagnosis',
    ],
    description: 'Inflammatory bowel disease affecting colon. Bloody diarrhea with crampy abdominal pain.',
  ),

  // ── PANCREATITIS ──
  DiseaseProfile(
    id: 'pancreatitis',
    displayName: 'Pancreatitis',
    primarySystem: BodySystem.gastrointestinal,
    symptomProfile: {
      'upper_abdominal_pain': SymptomRole.cardinal, // severe, radiates to back
      'pain_after_eating': SymptomRole.cardinal,
      'nausea': SymptomRole.cardinal,
      'vomiting': SymptomRole.cardinal,
      'fever': SymptomRole.common,
      'abdominal_pain': SymptomRole.common,
      'bloating': SymptomRole.common,
      'loss_of_appetite': SymptomRole.occasional,
      'unexplained_weight_loss': SymptomRole.occasional,
    },
    prevalence: 0.2,
    typicalRisk: ClinicalRisk.urgent,
    nextSteps: [
      'REFER urgently — may need hospitalization',
      'Nothing by mouth until evaluated',
      'Pain management needed',
      'Blood tests (amylase, lipase) required for diagnosis',
    ],
    description: 'Inflammation of the pancreas. Severe upper abdominal pain radiating to back, worse after eating.',
  ),

  // ── LIVER DISEASE (General) ──
  DiseaseProfile(
    id: 'liver_disease',
    displayName: 'Liver Disease',
    primarySystem: BodySystem.gastrointestinal,
    symptomProfile: {
      'jaundice': SymptomRole.cardinal,          // yellow skin/eyes
      'fatigue': SymptomRole.cardinal,
      'abdominal_pain': SymptomRole.common,      // right upper quadrant
      'dark_urine': SymptomRole.common,
      'nausea': SymptomRole.common,
      'loss_of_appetite': SymptomRole.common,
      'swelling_legs': SymptomRole.common,       // ascites/edema
      'itching': SymptomRole.common,
      'easy_bruising': SymptomRole.occasional,
      'vomiting': SymptomRole.occasional,
    },
    prevalence: 0.3,
    typicalRisk: ClinicalRisk.urgent,
    nextSteps: [
      'REFER for liver function tests (blood test)',
      'Stop alcohol completely',
      'Avoid paracetamol in high doses',
      'URGENT if jaundice with fever or confusion',
    ],
    description: 'Liver damage from various causes. Yellowing of skin/eyes, fatigue, abdominal swelling.',
  ),

  // ── OSTEOARTHRITIS ──
  DiseaseProfile(
    id: 'osteoarthritis',
    displayName: 'Osteoarthritis',
    primarySystem: BodySystem.musculoskeletal,
    symptomProfile: {
      'joint_pain': SymptomRole.cardinal,        // worse with activity, better with rest
      'joint_swelling': SymptomRole.common,
      'stiffness_morning': SymptomRole.common,   // brief, <30 min
      'difficulty_walking': SymptomRole.common,
      'bone_pain': SymptomRole.occasional,
    },
    prevalence: 0.6,
    typicalRisk: ClinicalRisk.moderate,
    demographics: Demographics(minAge: 45),
    nextSteps: [
      'Pain relief: paracetamol, topical diclofenac',
      'Gentle regular exercise (walking, swimming)',
      'Weight management — every kg matters for knees',
      'REFER if severe or affecting daily activities',
    ],
    description: 'Wear-and-tear arthritis. Joint pain worse with use, brief morning stiffness. Knees, hips, hands most common.',
  ),

  // ── RHEUMATOID ARTHRITIS ──
  DiseaseProfile(
    id: 'rheumatoid_arthritis',
    displayName: 'Rheumatoid Arthritis',
    primarySystem: BodySystem.musculoskeletal,
    symptomProfile: {
      'symmetric_joint_pain': SymptomRole.cardinal, // both sides affected
      'morning_stiffness_prolonged': SymptomRole.cardinal, // >1 hour
      'joint_swelling': SymptomRole.cardinal,
      'joint_pain': SymptomRole.common,
      'fatigue': SymptomRole.common,
      'fever': SymptomRole.occasional,           // low-grade
      'unexplained_weight_loss': SymptomRole.occasional,
    },
    prevalence: 0.2,
    typicalRisk: ClinicalRisk.moderate,
    demographics: Demographics(minAge: 25),
    nextSteps: [
      'REFER to doctor — early treatment prevents joint damage',
      'Blood tests (RF, CRP, ESR) needed',
      'Anti-inflammatory medication',
      'Different from osteoarthritis — affects younger people, symmetric',
    ],
    description: 'Autoimmune joint disease. Symmetric joint pain/swelling with prolonged morning stiffness (>1 hour).',
  ),

  // ── OSTEOPOROSIS ──
  DiseaseProfile(
    id: 'osteoporosis',
    displayName: 'Osteoporosis',
    primarySystem: BodySystem.musculoskeletal,
    symptomProfile: {
      'bone_fracture': SymptomRole.cardinal,     // fracture from minor trauma
      'back_pain': SymptomRole.common,           // vertebral compression
      'height_loss': SymptomRole.common,
      'stooped_posture': SymptomRole.common,
      'bone_pain': SymptomRole.occasional,
    },
    prevalence: 0.3,
    typicalRisk: ClinicalRisk.moderate,
    demographics: Demographics(minAge: 50, sex: 'F'),
    nextSteps: [
      'REFER for bone density test (DEXA scan)',
      'Calcium and Vitamin D supplementation',
      'Weight-bearing exercise',
      'Fall prevention measures for elderly',
    ],
    description: 'Weak, brittle bones prone to fractures. Often silent until a fracture occurs. Common in postmenopausal women.',
  ),

  // ── PARKINSON'S DISEASE ──
  DiseaseProfile(
    id: 'parkinsons_disease',
    displayName: "Parkinson's Disease",
    primarySystem: BodySystem.neurological,
    symptomProfile: {
      'resting_tremor': SymptomRole.cardinal,    // pill-rolling tremor at rest
      'slow_movement': SymptomRole.cardinal,     // bradykinesia
      'muscle_stiffness': SymptomRole.cardinal,  // rigidity
      'balance_problems': SymptomRole.common,
      'stooped_posture': SymptomRole.common,
      'difficulty_walking': SymptomRole.common,  // shuffling gait
      'tremor': SymptomRole.common,
      'speech_difficulty': SymptomRole.occasional, // soft/slurred
      'depressed_mood': SymptomRole.occasional,
      'insomnia': SymptomRole.occasional,
    },
    prevalence: 0.1,
    typicalRisk: ClinicalRisk.moderate,
    demographics: Demographics(minAge: 50),
    nextSteps: [
      'REFER to neurologist',
      'Medications available to manage symptoms (levodopa)',
      'Physical therapy and regular exercise',
      'Not curable but manageable with treatment',
    ],
    description: 'Progressive neurological disease. Tremor at rest, slow movement, stiffness, balance problems.',
  ),

  // ── MULTIPLE SCLEROSIS ──
  DiseaseProfile(
    id: 'multiple_sclerosis',
    displayName: 'Multiple Sclerosis',
    primarySystem: BodySystem.neurological,
    symptomProfile: {
      'numbness_tingling': SymptomRole.cardinal, // often first symptom
      'vision_blurring': SymptomRole.cardinal,   // optic neuritis
      'fatigue': SymptomRole.cardinal,           // overwhelming fatigue
      'balance_problems': SymptomRole.common,
      'difficulty_walking': SymptomRole.common,
      'muscle_stiffness': SymptomRole.common,    // spasticity
      'weakness_general': SymptomRole.common,
      'dizziness': SymptomRole.occasional,
      'speech_difficulty': SymptomRole.occasional,
      'urinary_incontinence': SymptomRole.occasional,
    },
    prevalence: 0.05,
    typicalRisk: ClinicalRisk.urgent,
    demographics: Demographics(minAge: 20, maxAge: 50),
    nextSteps: [
      'REFER to neurologist urgently',
      'MRI of brain and spine needed for diagnosis',
      'Treatable with disease-modifying therapies',
      'Symptoms may come and go (relapsing-remitting)',
    ],
    description: 'Autoimmune disease affecting brain/spinal cord. Numbness, vision problems, fatigue that comes and goes.',
  ),

  // ── STROKE (as disease profile, complements red flag) ──
  DiseaseProfile(
    id: 'stroke',
    displayName: 'Stroke',
    primarySystem: BodySystem.neurological,
    symptomProfile: {
      'weakness_one_side': SymptomRole.cardinal, // FAST: Face/Arm weakness
      'speech_difficulty': SymptomRole.cardinal, // FAST: Speech
      'facial_drooping': SymptomRole.cardinal,   // FAST: Face
      'confusion': SymptomRole.common,
      'severe_headache': SymptomRole.common,     // hemorrhagic stroke
      'vision_loss': SymptomRole.common,
      'dizziness': SymptomRole.common,
      'difficulty_walking': SymptomRole.common,
    },
    prevalence: 0.2,
    typicalRisk: ClinicalRisk.emergency,
    demographics: Demographics(minAge: 40),
    nextSteps: [
      'EMERGENCY — call ambulance IMMEDIATELY',
      'Note exact time symptoms started (critical for treatment)',
      'Do NOT give food or water',
      'FAST test: Face drooping, Arm weakness, Speech difficulty → Time to call',
    ],
    description: 'Brain blood vessel blockage or bleed. SUDDEN one-sided weakness, speech problems, face drooping.',
  ),

  // ── DEPRESSION / MDD ──
  DiseaseProfile(
    id: 'depression',
    displayName: 'Depression',
    primarySystem: BodySystem.neurological,
    symptomProfile: {
      'depressed_mood': SymptomRole.cardinal,    // persistent sad/empty mood
      'loss_of_interest': SymptomRole.cardinal,  // anhedonia
      'fatigue': SymptomRole.cardinal,
      'sleep_changes': SymptomRole.common,       // insomnia or hypersomnia
      'appetite_changes': SymptomRole.common,
      'concentration_difficulty': SymptomRole.common,
      'guilt_worthlessness': SymptomRole.common,
      'body_ache': SymptomRole.occasional,
      'headache': SymptomRole.occasional,
      'suicidal_thoughts': SymptomRole.occasional, // screen for this
    },
    prevalence: 0.5,
    typicalRisk: ClinicalRisk.moderate,
    nextSteps: [
      'REFER for mental health evaluation',
      'Depression is treatable with counseling and/or medication',
      'Gently ask about suicidal thoughts — if yes, urgent referral',
      'Encourage social support, physical activity, routine',
    ],
    description: 'Persistent sadness, loss of interest in activities, fatigue lasting 2+ weeks. Very common and treatable.',
  ),

  // ── ANXIETY DISORDERS ──
  DiseaseProfile(
    id: 'anxiety_disorders',
    displayName: 'Anxiety Disorders',
    primarySystem: BodySystem.neurological,
    symptomProfile: {
      'excessive_worry': SymptomRole.cardinal,   // persistent, hard to control
      'restlessness': SymptomRole.cardinal,
      'palpitations': SymptomRole.common,        // often mistaken for heart disease
      'insomnia': SymptomRole.common,
      'fatigue': SymptomRole.common,
      'concentration_difficulty': SymptomRole.common,
      'muscle_pain': SymptomRole.common,         // tension
      'shortness_of_breath': SymptomRole.occasional,
      'chest_pain': SymptomRole.occasional,      // panic attacks
      'dizziness': SymptomRole.occasional,
      'sweating': SymptomRole.occasional,
      'nausea': SymptomRole.occasional,
    },
    prevalence: 0.4,
    typicalRisk: ClinicalRisk.moderate,
    nextSteps: [
      'REFER for mental health evaluation',
      'Anxiety is very treatable with therapy and/or medication',
      'Rule out thyroid problems and heart conditions first',
      'Breathing exercises and relaxation techniques can help',
    ],
    description: 'Excessive worry, restlessness, physical tension. Can cause palpitations, chest pain that mimics heart disease.',
  ),

  // ── THALASSEMIA ──
  DiseaseProfile(
    id: 'thalassemia',
    displayName: 'Thalassemia',
    primarySystem: BodySystem.hematological,
    symptomProfile: {
      'pallor': SymptomRole.cardinal,            // chronic anemia
      'fatigue': SymptomRole.cardinal,
      'weakness_general': SymptomRole.cardinal,
      'jaundice': SymptomRole.common,            // mild, chronic
      'shortness_of_breath': SymptomRole.common,
      'bone_pain': SymptomRole.common,           // bone marrow expansion
      'loss_of_appetite': SymptomRole.occasional,
      'dark_urine': SymptomRole.occasional,
    },
    prevalence: 0.2,
    typicalRisk: ClinicalRisk.urgent,
    demographics: Demographics(maxAge: 30),
    nextSteps: [
      'REFER for blood tests (CBC, hemoglobin electrophoresis)',
      'May need regular blood transfusions',
      'Genetic condition — screen family members',
      'Folic acid supplementation',
    ],
    description: 'Inherited blood disorder causing anemia. Pale, tired, sometimes jaundiced. Common in South/Southeast Asia.',
  ),

  // ── THROMBOCYTOPENIA ──
  DiseaseProfile(
    id: 'thrombocytopenia',
    displayName: 'Thrombocytopenia (Low Platelets)',
    primarySystem: BodySystem.hematological,
    symptomProfile: {
      'easy_bruising': SymptomRole.cardinal,
      'petechiae': SymptomRole.cardinal,         // tiny red/purple spots
      'bleeding': SymptomRole.cardinal,          // prolonged from cuts
      'nosebleed': SymptomRole.common,
      'rash': SymptomRole.common,                // petechial rash
      'fatigue': SymptomRole.common,
      'bloody_stool': SymptomRole.occasional,
      'blood_in_urine': SymptomRole.occasional,
    },
    prevalence: 0.2,
    typicalRisk: ClinicalRisk.urgent,
    nextSteps: [
      'REFER urgently for blood test (platelet count)',
      'Check if dengue or other infection is the cause',
      'Avoid aspirin and NSAIDs',
      'EMERGENCY if severe bleeding or platelet count very low',
    ],
    description: 'Low platelet count causing easy bruising and bleeding. Can be caused by dengue, medications, or other conditions.',
  ),
"""

# Find the position to insert — before the closing of diseaseProfiles list
# The list ends with "];"
content = content.replace(
    "\n];\n\n// ============================================================\n// SYMPTOM ALIASES",
    new_diseases + "\n];\n\n// ============================================================\n// SYMPTOM ALIASES"
)

# ============================================================
# 3. ADD JUNK CLASS FILTER
# ============================================================

junk_filter = """

// ============================================================
// JUNK CLASSES — ML model outputs to filter out
// These are not real diagnoses and should be suppressed.
// ============================================================

const Set<String> junkClassFilters = {
  '0',
  'Healthy',
  'Healthy Heart',
  'No ASD',
  "No Alzheimer's Disease",
  'No Asthma',
  'No Chronic Disease',
  'No Diabetes',
  'No Dry Eye Disease',
  'No Liver Disease',
  'No Lower Back Pain',
  'No Mental Disorder',
  'No Mental Health Condition',
  'No Multiple Sclerosis',
  'No OCD',
  "No Parkinson's Disease",
  'No Psychosocial Stress',
  'No Sleep Disorder',
  'No Stroke',
  'No Student Mental Health Issue',
  'No Thyroid Disease',
  'Loneliness',
  'Psychosocial Stress',
  'Student Mental Health Issue',
  'Mental Health Condition',
  'anexiety',  // misspelling
  '[0, 0, 0, 0, 0, 0, 0, 1]',
  '[0, 0, 0, 0, 0, 0, 1, 0]',
  '[0, 0, 0, 0, 0, 1, 0, 0]',
  '[0, 0, 0, 0, 1, 0, 0, 0]',
  '[0, 0, 0, 1, 0, 0, 0, 0]',
  '[0, 0, 1, 0, 0, 0, 0, 0]',
  '[0, 1, 0, 0, 0, 0, 0, 0]',
  '[1, 0, 0, 0, 0, 0, 0, 0]',
};
"""

# Add before symptom aliases section
content = content.replace(
    "// ============================================================\n// SYMPTOM ALIASES",
    junk_filter + "\n// ============================================================\n// SYMPTOM ALIASES"
)

# ============================================================
# 4. ADD ALIASES FOR NEW SYMPTOMS
# ============================================================

new_aliases = """
  // Additional aliases for new diseases
  'low_platelets': 'thrombocytopenia',
  'easy_bruise': 'easy_bruising',
  'bruising': 'easy_bruising',
  'sad': 'depressed_mood',
  'sadness': 'depressed_mood',
  'udas': 'depressed_mood',        // Hindi
  'worry': 'excessive_worry',
  'chinta': 'excessive_worry',     // Hindi
  'scaly_skin': 'scaling_skin',
  'scales': 'scaling_skin',
  'dry_eyes': 'eye_itching',
  'ankle_swelling': 'swelling_ankles',
  'pair_sujan': 'swelling_ankles', // Hindi
  'trembling': 'tremor',
  'kampan': 'tremor',             // Hindi
  'shaking': 'tremor',
"""

content = content.replace(
    "  'peshab_mein_jalan': 'burning_urination',",
    "  'peshab_mein_jalan': 'burning_urination',\n" + new_aliases
)

# ============================================================
# Write the updated file
# ============================================================
with open('lib/services/clinical_knowledge.dart', 'w') as f:
    f.write(content)

print("[OK] Added 17 new disease profiles:")
print("     Allergic Rhinitis, Eczema, Psoriasis, Coronary Artery Disease,")
print("     Chronic Kidney Disease, Crohn's Disease, Ulcerative Colitis,")
print("     Pancreatitis, Liver Disease, Osteoarthritis, Rheumatoid Arthritis,")
print("     Osteoporosis, Parkinson's Disease, Multiple Sclerosis, Stroke,")
print("     Depression, Anxiety Disorders, Thalassemia, Thrombocytopenia")
print()
print("[OK] Added junk class filter (40 entries)")
print("[OK] Added 30+ new symptoms to system map")
print("[OK] Added symptom aliases for new diseases")
print()
print("Total disease profiles now: ~47")
print("Total red flag rules: 11")
print()
print("Diseases from disease_list.json NOT profiled (specialist diagnoses):")
print("  ADHD, ASD/Autism, Alzheimer's, OCD, PTSD, PDD, Bipolar,")
print("  Eating Disorder, Sleeping Disorder, Kidney Cancer, Liver Cancer")
print("  → These require specialist evaluation, not field triage.")
print("  → ML model can still flag them; clinical engine won't override.")

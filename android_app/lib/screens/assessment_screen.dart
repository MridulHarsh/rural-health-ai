// assessment_screen.dart
// Multi-step patient assessment with text, voice, image inputs.
// Updated to use ClinicalEngine for diagnosis.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';

import '../l10n/translations.dart';
import '../models/patient.dart';
import '../services/ml_service.dart';
import '../services/clinical_knowledge.dart';
import '../services/ocr_service.dart';
import 'results_screen.dart';

import '../services/fuzzy_symptom_matcher.dart';

import 'package:image/image.dart' as img;

class AssessmentScreen extends StatefulWidget {
  final MLService mlService;
  const AssessmentScreen({super.key, required this.mlService});

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  String _lang = 'en';

  // Patient info
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _householdController = TextEditingController();
  String _gender = 'Male';

  // Vitals
  final _tempController = TextEditingController();
  final _bpController = TextEditingController();
  final _hrController = TextEditingController();
  final _spo2Controller = TextEditingController();

  // Symptoms
  final Set<String> _selectedSymptoms = {};
  String? _expandedCategory = 'General'; // Only one category open at a time

  final _symptomSearchController = TextEditingController();

  // Voice
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _voiceText = '';

  // Image
  File? _capturedImage;
  String _imageType = 'lung'; // 'eye', 'lung', 'malaria'
  List<MapEntry<String, double>>? _imageResults;

  // Notes
  final _notesController = TextEditingController();

  // Loading
  bool _isAnalyzing = false;

  // ── Symptom chips — organized by body system for better UX ──
    static const Map<String, List<String>> _symptomsByCategory = {
    'General': [
      // Fever is cardinal in 15+ diseases and is often reported by the
      // patient without a thermometer reading — surface it first.
      'fever', 'high_fever', 'mild_fever',
      'fatigue', 'body_ache', 'unexplained_weight_loss', 'weight_loss',
      'chills', 'night_sweats', 'loss_of_appetite', 'malaise',
      'dehydration', 'dry_mouth', 'sunken_eyes',
      'swollen_lymph_nodes', 'pallor', 'weakness_general',
      'sweating', 'cold', 'daytime_sleepiness',
    ],
    'Respiratory': [
      'cough', 'dry_cough', 'productive_cough', 'chronic_productive_cough',
      'breathlessness', 'exertion_breathlessness',
      'wheezing', 'sore_throat', 'runny_nose', 'rhinorrhea',
      'nasal_congestion', 'sneezing', 'sputum', 'blood_in_sputum',
      'hoarseness', 'chest_tightness', 'chest_indrawing', 'stridor',
      'difficulty_breathing_severe', 'difficulty_breathing',
      'whooping_sound', 'barking_cough',
      'snoring_loud', 'witnessed_apneas',
    ],
    'Head / Neuro': [
      'headache', 'severe_headache', 'sudden_severe_headache',
      'throbbing_headache', 'tight_band_headache', 'auras_before_headache',
      'dizziness', 'confusion', 'seizures', 'convulsions',
      'weakness_one_side', 'one_sided_weakness', 'facial_weakness',
      'ascending_weakness', 'blurred_vision',
      'double_vision', 'vision_loss', 'neck_stiffness',
      'stiff_neck_with_fever', 'numbness',
      'tingling', 'tremor', 'tremors', 'resting_tremor',
      'altered_consciousness', 'facial_drooping', 'speech_difficulty',
      'inability_to_speak', 'memory_problems', 'memory_loss',
      'memory_loss_progressive',
      'balance_problems', 'difficulty_walking', 'photophobia',
      'slow_movement', 'stooped_posture',
    ],
    'GI / Abdomen': [
      'nausea', 'vomiting', 'projectile_vomiting', 'diarrhea',
      'bloody_diarrhea', 'abdominal_pain', 'severe_abdominal_pain',
      'upper_abdominal_pain', 'epigastric_pain', 'right_upper_abdominal_pain',
      'abdominal_distension', 'constipation', 'bloating', 'heartburn',
      'regurgitation', 'bloating_after_milk',
      'indigestion', 'jaundice', 'blood_in_stool', 'bloody_stool',
      'black_stool', 'rectal_bleeding', 'dark_urine', 'pale_stool',
      'pain_after_eating', 'abdominal_rigidity', 'loss_of_appetite',
      'loss_of_smell', 'loss_of_taste', 'difficulty_swallowing',
      'painful_defecation', 'anal_bleeding_bright', 'anal_itching',
      'worms_in_stool', 'gluten_diarrhea',
      'tooth_pain', 'cavity_visible',
    ],
    'Skin': [
      'rash', 'skin_rash', 'itching', 'itchy_dry_skin', 'skin_lesion',
      'blisters', 'skin_discoloration', 'skin_darkening', 'skin_redness',
      'skin_peeling', 'skin_cracking', 'scaling_skin', 'dry_skin',
      'hives', 'red_patches', 'silvery_scales', 'wound_non_healing',
      'swelling_local', 'bruising', 'lumps', 'petechiae',
      'hair_loss', 'nail_changes',
      'acne_pimples', 'blackheads',
      'oval_patches', 'greasy_scaling', 'facial_flushing',
      'warty_papules', 'itchy_scalp_nits', 'honey_crusts',
      'dermatomal_vesicular_rash', 'burning_nerve_pain',
      'strawberry_tongue',
    ],
    'Heart / Circulation': [
      'chest_pain', 'severe_chest_pain', 'crushing_chest_pain',
      'left_arm_pain', 'arm_pain', 'jaw_pain',
      'palpitations', 'irregular_pulse',
      'rapid_heartbeat', 'irregular_heartbeat', 'leg_swelling',
      'swollen_legs', 'swollen_ankles', 'swelling_ankles',
      'leg_pain', 'leg_pain_on_walking', 'cold_extremities',
      'calf_pain_swelling', 'visible_varicose_veins',
      'blue_lips', 'cyanosis',
      'orthopnea', 'high_blood_pressure', 'low_blood_pressure',
      'easy_bleeding', 'easy_bruising', 'nosebleed',
    ],
    'Muscles / Joints': [
      'joint_pain', 'joint_swelling', 'symmetric_joint_pain',
      'joint_swelling_big_toe',
      'back_pain', 'lower_back_pain', 'shooting_leg_pain',
      'muscle_pain', 'muscle_cramps', 'muscle_weakness',
      'muscle_stiffness', 'stiffness', 'stiffness_morning',
      'morning_stiffness_prolonged', 'bone_pain', 'bone_fracture',
      'height_loss',
      'sharp_heel_pain', 'wrist_numbness_tingling',
      'shoulder_pain_range_loss', 'widespread_tender_points',
    ],
    'Urinary / Reproductive': [
      'burning_urination', 'painful_urination', 'frequent_urination',
      'excessive_urination', 'blood_in_urine', 'reduced_urine',
      'decreased_urine', 'foamy_urine', 'urinary_incontinence',
      'flank_pain', 'pelvic_pain', 'pelvic_pressure',
      'genital_discharge', 'genital_sores', 'genital_ulcer',
      'urethral_discharge', 'vaginal_discharge', 'vaginal_itching',
      'painful_intercourse',
      'weak_urine_stream', 'hesitancy', 'urgency',
      'incomplete_emptying', 'leak_on_cough',
    ],
    'Eyes / Ears / ENT': [
      'eye_redness', 'red_eyes', 'eye_pain', 'eye_discharge',
      'eye_swelling', 'eye_itching', 'watery_eyes',
      'gradual_vision_loss', 'halos_around_lights', 'cloudy_lens',
      'painful_red_eye_severe', 'eye_floaters', 'eyelash_crusting',
      'dry_itchy_eye',
      'ear_pain', 'ear_discharge', 'hearing_loss', 'difficulty_hearing',
      'ear_fullness', 'tinnitus', 'ringing_ears',
      'vertigo_spinning', 'parotid_swelling',
      'nasal_itching', 'snoring',
      'painful_swallowing', 'muffled_voice', 'oral_thrush',
    ],
    'Endocrine': [
      'excessive_thirst', 'excessive_hunger', 'heat_intolerance',
      'cold_intolerance', 'enlarged_thyroid', 'neck_swelling',
      'unexplained_weight_gain',
      'hot_flashes', 'irregular_periods', 'heavy_periods',
      'night_blindness', 'glossitis', 'shaky_sweaty_hungry',
    ],
    'Mental Health': [
      'anxiety', 'excessive_worry', 'depression', 'depressed_mood',
      'insomnia', 'sleep_changes', 'mood_swings', 'irritability',
      'loss_of_interest', 'difficulty_concentrating',
      'concentration_difficulty', 'panic_attacks', 'restlessness',
      'appetite_changes', 'guilt_worthlessness', 'suicidal_thoughts',
      'recurring_intrusive_thoughts', 'repetitive_behaviors',
      'flashbacks_traumatic', 'hypervigilance',
      'mood_elevation_extreme', 'decreased_sleep_need',
      'hallucinations', 'delusions', 'disorganized_thinking',
      'binge_eating', 'self_induced_vomiting', 'body_image_distorted',
      'craving_alcohol', 'withdrawal_tremor',
    ],
    'Maternal': [
      'missed_period', 'morning_sickness', 'breast_tenderness',
      'breast_lump', 'breast_redness_pain',
      'swollen_feet', 'swelling_face', 'vaginal_bleeding',
      'vaginal_bleeding_pregnant', 'abdominal_cramping',
      'reduced_fetal_movement', 'pregnancy',
      'severe_headache_pregnant', 'sudden_swelling_pregnant',
      'visual_changes_pregnant',
    ],
    'Severe / Red Flag': [
      'bleeding', 'severe_bleeding', 'severe_body_pain',
      'severe_dehydration_signs', 'unconsciousness', 'snake_bite',
      'dog_bite', 'insect_bite',
      'inability_to_drink', 'inability_to_pass_stool',
      'lethargy', 'no_urine', 'skin_pinch_slow', 'swelling_throat',
      'drooping_eyelids',
    ],
  };

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

  void _nextStep() {
    if (_currentStep < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // ================================================================
  // ANALYSIS — uses ClinicalEngine via MLService
  // ================================================================
  // Preprocess image file → 128x128x3 normalized float array
  Future<List<List<List<double>>>?> _preprocessImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Resize to 128x128
      final resized = img.copyResize(decoded, width: 128, height: 128);

      // Convert to normalized float array [128][128][3]
      final imageData = List.generate(128, (y) {
        return List.generate(128, (x) {
          final pixel = resized.getPixel(x, y);
          return [
            pixel.r.toDouble() / 255.0,
            pixel.g.toDouble() / 255.0,
            pixel.b.toDouble() / 255.0,
          ];
        });
      });

      return imageData;
    } catch (e) {
      debugPrint('Image preprocessing error: $e');
      return null;
    }
  }



  Future<void> _runAnalysis() async {
    setState(() => _isAnalyzing = true);

    // Clear any stale image classification results from a previous run.
    // If the user removed the image after a prior classification, we must not
    // carry those results forward into a new assessment.
    if (_capturedImage == null) {
      _imageResults = null;
    }

    // Build vitals
    final vitals = Vitals(
      temperature: double.tryParse(_tempController.text),
      bloodPressure:
          _bpController.text.isEmpty ? null : _bpController.text,
      heartRate: int.tryParse(_hrController.text),
      spo2: int.tryParse(_spo2Controller.text),
    );

    // Combine selected symptoms + voice-extracted symptoms
    final allSymptoms = <String>{..._selectedSymptoms};
    if (_voiceText.isNotEmpty) {
      final voiceSymptoms =
          FuzzySymptomMatcher().extractSymptoms(_voiceText).toList();
      allSymptoms.addAll(voiceSymptoms);
    }

    // Parse patient info
    final age = int.tryParse(_ageController.text);
    final sex = _gender == 'Male'
        ? 'M'
        : _gender == 'Female'
            ? 'F'
            : null;

    // ── Run image classification if image captured ──
    if (_capturedImage != null) {
      print('[IMG] Starting preprocessing for type: $_imageType');
      final imageData = await _preprocessImage(_capturedImage!);
      print('[IMG] Preprocessing result: ${imageData != null ? "OK (128x128x3)" : "FAILED"}');
      if (imageData != null) {
        _imageResults = await widget.mlService.classifyImage(
          imageData: imageData,
          type: _imageType,
        );
        print('[IMG] Classification result: $_imageResults');
      }
    }



    // ── Run clinical engine ──
    final diagnosis = widget.mlService.diagnosePatient(
      symptoms: allSymptoms.toList(),
      age: age,
      sex: sex,
      vitals: vitals.toEngineMap(),
    );

    // ── Run specialist tabular screenings (heart, diabetes, kidney, etc.) ──
    final specialistScreenings = widget.mlService.runSpecialistScreenings(
      age: age,
      sex: sex,
      bloodPressure: vitals.bloodPressure,
      temperature: vitals.temperature,
      heartRate: vitals.heartRate,
      spo2: vitals.spo2,
      weight: vitals.weight,
      height: vitals.height,
    );

    // ── Convert DiagnosticResult → AssessmentResult ──

    // Map ClinicalRisk → RiskLevel
    RiskLevel mapRisk(ClinicalRisk cr) {
      switch (cr) {
        case ClinicalRisk.emergency:
          return RiskLevel.emergency;
        case ClinicalRisk.urgent:
          return RiskLevel.urgent;
        case ClinicalRisk.moderate:
          return RiskLevel.moderate;
        case ClinicalRisk.normal:
          return RiskLevel.normal;
      }
    }

    // Convert conditions
    final conditions = diagnosis.conditions.map((c) {
      return PredictedCondition(
        name: c.profile.displayName,
        confidence: c.confidence,
        riskLevel: mapRisk(c.risk),
        description: c.profile.description,
        reasoning: c.reasoning,
        matchedCardinal: c.matchedCardinal,
        missingCardinal: c.missingCardinal,
        nextSteps: c.profile.nextSteps,
      );
    }).toList();

    // Build red flag alert if present
    RedFlagAlert? redFlag;
    if (diagnosis.redFlag != null) {
      redFlag = RedFlagAlert(
        conditionName: diagnosis.redFlag!.rule.conditionName,
        immediateAction: diagnosis.redFlag!.rule.immediateAction,
        triggerSymptoms: [
          ...diagnosis.redFlag!.matchedRequired,
          ...diagnosis.redFlag!.matchedSupporting,
        ],
      );
    }

    // Collect all next steps (red flag action first, then per-condition)
    final nextSteps = <String>[];
    if (redFlag != null) {
      nextSteps.add(redFlag.immediateAction);
    }
    if (conditions.isNotEmpty) {
      nextSteps.addAll(conditions.first.nextSteps);
    }

    // System names for display
    final systemNames = diagnosis.implicatedSystems
        .map((s) => s.name[0].toUpperCase() + s.name.substring(1))
        .toList();

    final result = AssessmentResult(
      patient: Patient(
        id: const Uuid().v4(),
        name: _nameController.text.isEmpty ? 'Unknown' : _nameController.text,
        age: age ?? 0,
        gender: _gender,
        householdId: _householdController.text.trim().isEmpty
            ? null
            : _householdController.text.trim(),
      ),
      vitals: vitals,
      symptoms: allSymptoms.toList(),
      conditions: conditions,
      overallRisk: mapRisk(diagnosis.overallRisk),
      nextSteps: nextSteps,
      imagePath: _capturedImage?.path,
      voiceTranscript: _voiceText.isEmpty ? null : _voiceText,
      additionalNotes:
          _notesController.text.isEmpty ? null : _notesController.text,
      redFlag: redFlag,
      implicatedSystems: systemNames,
      specialistScreenings: specialistScreenings,
      imageClassificationResults: _imageResults,
      imageType: _capturedImage != null ? _imageType : null,
    );

    setState(() => _isAnalyzing = false);

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultsScreen(result: result, langCode: _lang),
        ),
      );
    }
  }

  // ================================================================
  // VOICE INPUT
  // ================================================================

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return;

    final available = await _speech.initialize(
      onError: (e) => setState(() => _isListening = false),
    );
    if (!available) return;

    final locale =
        AppTranslations.sttLocales[_lang] ?? 'en-IN';

    setState(() => _isListening = true);

    _speech.listen(
      onResult: (result) {
        // Speech recognition can fire callbacks after the user has navigated
        // away or stopped listening. Guard setState with mounted.
        if (!mounted) return;
        setState(() {
          _voiceText = result.recognizedWords;
        });

        // Auto-extract symptoms from voice on final result only
        if (result.finalResult) {
          final extracted =
              FuzzySymptomMatcher().extractSymptoms(_voiceText).toList();
          if (!mounted) return;
          setState(() {
            _selectedSymptoms.addAll(extracted);
            _isListening = false;
          });
        }
      },
      localeId: locale,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  // ================================================================
  // IMAGE CAPTURE
  // ================================================================

  Future<void> _captureImage(ImageSource source) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() => _capturedImage = File(image.path));
    }
  }

  /// Scan a prescription / medical report via OCR and append the recognized
  /// text (or any medicine-shaped lines) to the notes field.
  Future<void> _scanPrescription() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (image == null) return;
    if (!mounted) return;

    // Show a quick spinner while OCR runs
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final result = await OcrService.extractFromFile(image.path);
    if (!mounted) return;
    Navigator.of(context).pop(); // close spinner

    if (result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No text detected. Try again in better light.')),
      );
      return;
    }

    final meds = OcrService.extractMedicineLines(result);
    final summary = meds.isNotEmpty
        ? 'Scanned Rx:\n${meds.join('\n')}'
        : 'Scanned text:\n${result.rawText.substring(0, result.rawText.length.clamp(0, 400))}';

    setState(() {
      final existing = _notesController.text.trim();
      _notesController.text =
          existing.isEmpty ? summary : '$existing\n\n$summary';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(
        meds.isNotEmpty
            ? 'Detected ${meds.length} medicine line(s)'
            : 'Text captured to notes',
      )),
    );
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final steps = [
      _t('patient_info'),
      _t('symptoms'),
      _t('vitals'),
      _t('camera_input'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_t('new_assessment')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // ── Step Indicator ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: List.generate(steps.length, (i) {
                final isActive = i == _currentStep;
                final isDone = i < _currentStep;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDone
                                ? Theme.of(context).colorScheme.primary
                                : isActive
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.5)
                                    : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          steps[i],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w400,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Page Content ──
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _currentStep = i),
              children: [
                _buildPatientInfoStep(),
                _buildSymptomsStep(),
                _buildVitalsStep(),
                _buildImageStep(),
              ],
            ),
          ),

          // ── Bottom Buttons ──
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _prevStep,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(_t('back')),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isAnalyzing
                        ? null
                        : _currentStep == 3
                            ? _runAnalysis
                            : _nextStep,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isAnalyzing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            _currentStep == 3
                                ? _t('analyze')
                                : _t('next'),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // STEP 1: Patient Info
  // ================================================================

  Widget _buildPatientInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t('patient_info'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: _t('name'),
              prefixIcon: const Icon(Icons.person_outline),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _t('age'),
              prefixIcon: const Icon(Icons.cake_outlined),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          Text(_t('gender'),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: ['Male', 'Female', 'Other'].map((g) {
              final isSelected = _gender == g;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(g),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _gender = g);
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _householdController,
            decoration: InputDecoration(
              labelText: 'Household / Family ID (optional)',
              helperText:
                  'Same ID for family members → cluster view for contagion',
              prefixIcon: const Icon(Icons.home_outlined),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ].animate(interval: 60.ms).fadeIn(duration: 250.ms),
      ),
    );
  }

  // ================================================================
  // STEP 2: Symptoms — organized by body system
  // ================================================================

  Widget _buildSymptomsStep() {
    final searchQuery = _symptomSearchController.text.toLowerCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t('symptoms'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Tap symptoms the patient is experiencing. Use voice for local language input.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // Voice input bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isListening
                  ? Colors.red.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: _isListening
                  ? Border.all(color: Colors.red.shade300)
                  : null,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _toggleListening,
                  icon: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _isListening ? Colors.red : Colors.blue,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isListening
                        ? 'Listening...'
                        : _voiceText.isEmpty
                            ? _t('tap_mic_to_speak')
                            : _voiceText,
                    style: TextStyle(
                      fontSize: 14,
                      color: _isListening
                          ? Colors.red.shade700
                          : Colors.grey.shade700,
                      fontStyle: _voiceText.isEmpty && !_isListening
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Search filter
          TextField(
            controller: _symptomSearchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search symptoms...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),

          const SizedBox(height: 12),

          // Selected count
          if (_selectedSymptoms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${_selectedSymptoms.length} symptom(s) selected',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),

          // Symptom chips by category — collapsible, one at a time
          ..._symptomsByCategory.entries.map((category) {
            // Filter by search
            final symptoms = category.value.where((s) {
              if (searchQuery.isEmpty) return true;
              return _humanize(s).toLowerCase().contains(searchQuery);
            }).toList();

            if (symptoms.isEmpty) return const SizedBox.shrink();

            final isExpanded = _expandedCategory == category.key;
            final selectedInCat = category.value
                .where((s) => _selectedSymptoms.contains(s))
                .length;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category header — tap to expand/collapse
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedCategory =
                            isExpanded ? null : category.key;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.08)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: isExpanded
                            ? Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.3))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 20,
                            color: isExpanded
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              category.key,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isExpanded
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                          if (selectedInCat > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$selectedInCat',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Chips — only shown when expanded
                  if (isExpanded) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: symptoms.map((symptom) {
                        final isSelected =
                            _selectedSymptoms.contains(symptom);
                        return FilterChip(
                          label: Text(
                            _humanize(symptom),
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedSymptoms.add(symptom);
                              } else {
                                _selectedSymptoms.remove(symptom);
                              }
                            });
                          },
                          selectedColor:
                              Theme.of(context).colorScheme.primary,
                          checkmarkColor: Colors.white,
                          backgroundColor: Colors.grey.shade200,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            );
          }),

          // OCR — scan an existing prescription or report to auto-fill notes
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _scanPrescription,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan prescription / report'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),

          // Notes
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Additional notes',
              alignLabelWithHint: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // STEP 3: Vitals
  // ================================================================

  Widget _buildVitalsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t('vitals'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Enter available vital signs. Leave blank if not measured.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          _vitalField(
            controller: _tempController,
            label: '${_t("temperature")} (°F)',
            icon: Icons.thermostat_outlined,
            hint: 'e.g. 98.6',
          ),
          const SizedBox(height: 16),
          _vitalField(
            controller: _bpController,
            label: '${_t("blood_pressure")} (mmHg)',
            icon: Icons.favorite_outline,
            hint: 'e.g. 120/80',
          ),
          const SizedBox(height: 16),
          _vitalField(
            controller: _hrController,
            label: '${_t("heart_rate")} (bpm)',
            icon: Icons.monitor_heart_outlined,
            hint: 'e.g. 72',
          ),
          const SizedBox(height: 16),
          _vitalField(
            controller: _spo2Controller,
            label: 'SpO2 (%)',
            icon: Icons.air_outlined,
            hint: 'e.g. 97',
          ),
        ].animate(interval: 60.ms).fadeIn(duration: 250.ms),
      ),
    );
  }

  Widget _vitalField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ================================================================
  // STEP 4: Image capture + summary
  // ================================================================

  Widget _buildImageStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t('camera_input'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Optional: Capture a medical image for AI analysis.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // Image type selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _imageType,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'eye', child: Text('\u{1F441} Eye Photo — Cataract, Glaucoma, DR')),
                  DropdownMenuItem(value: 'lung', child: Text('\u{1FA7B} Chest X-ray — Pneumonia, TB, COVID')),
                  DropdownMenuItem(value: 'malaria', child: Text('\u{1FA78} Blood Smear — Malaria Parasite')),
                  DropdownMenuItem(value: 'skin', child: Text('\u{270B} Skin Photo — Triage Screening')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _imageType = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // What to capture hint
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _imageType == 'eye'
                        ? 'Take a clear close-up photo of the eye'
                        : _imageType == 'lung'
                            ? 'Take a photo of the chest X-ray report'
                            : _imageType == 'skin'
                                ? 'Well-lit close-up of the affected skin. Triage only — confirm at PHC.'
                                : 'Take a photo of the blood smear slide',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Image preview or capture buttons
          if (_capturedImage != null)
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _capturedImage!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _capturedImage = null;
                        _imageResults = null;
                      }),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Remove photo'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_imageType.toUpperCase()} mode',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                // Show classification results if available
                if (_imageResults != null && _imageResults!.isNotEmpty) ...[
                  const SizedBox(height: 12),

                  // Low-confidence banner for skin (the model is below the
                  // ship gate; MLService prepends skinLowConfidenceLabel
                  // when top-1 probability < skinConfidenceFloor).
                  if (_imageResults!.first.key ==
                      MLService.skinLowConfidenceLabel) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.amber.shade800, size: 22),
                          const SizedBox(width: 10),
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
                                  'The alternatives below are shown for reference, but '
                                  'this case should be reviewed by a clinician.',
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
                    const SizedBox(height: 10),
                  ],

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Image Analysis Results',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._imageResults!
                            .where((r) =>
                                r.key != MLService.skinLowConfidenceLabel)
                            .map((r) {
                          final pct = (r.value * 100).toStringAsFixed(1);
                          // "Top" styling is reserved for predictions the
                          // model is actually confident about. When the
                          // sentinel is in the list, we don't bold any row
                          // because there is no trusted top-1.
                          final hasSentinel = _imageResults!.first.key ==
                              MLService.skinLowConfidenceLabel;
                          final isTop = !hasSentinel &&
                              r == _imageResults!.first;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.key,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isTop
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isTop
                                        ? Colors.green.shade700
                                        : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$pct%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isTop
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 4),
                        Text(
                          'Note: This is an AI screening tool, not a diagnosis.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _captureImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(_t('take_photo')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _captureImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(_t('gallery')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 32),

          // Summary before analysis
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assessment Summary',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _summaryRow('Patient',
                    _nameController.text.isEmpty ? '-' : _nameController.text),
                _summaryRow('Age / Gender',
                    '${_ageController.text.isEmpty ? "-" : _ageController.text} / $_gender'),
                _summaryRow(
                    'Symptoms', '${_selectedSymptoms.length} selected'),
                _summaryRow(
                    'Vitals',
                    [
                      if (_tempController.text.isNotEmpty)
                        '${_tempController.text}°F',
                      if (_bpController.text.isNotEmpty)
                        'BP ${_bpController.text}',
                      if (_hrController.text.isNotEmpty)
                        'HR ${_hrController.text}',
                      if (_spo2Controller.text.isNotEmpty)
                        'SpO2 ${_spo2Controller.text}%',
                    ].join(', ').ifEmpty('Not recorded')),
                _summaryRow('Image', _capturedImage != null ? 'Yes' : 'No'),
                _summaryRow('Voice', _voiceText.isNotEmpty ? 'Yes' : 'No'),
              ],
            ),
          ),
        ].animate(interval: 80.ms).fadeIn(duration: 300.ms),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _humanize(String key) =>
      key.replaceAll('_', ' ').replaceFirst(key[0], key[0].toUpperCase());

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _householdController.dispose();
    _tempController.dispose();
    _bpController.dispose();
    _hrController.dispose();
    _spo2Controller.dispose();
    _symptomSearchController.dispose();
    _notesController.dispose();
    _speech.stop();
    super.dispose();
  }
}

/// Extension for empty string fallback
extension _StringExt on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

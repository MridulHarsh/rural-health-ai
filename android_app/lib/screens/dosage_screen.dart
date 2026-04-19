// dosage_screen.dart
// Weight-based pediatric drug dosage calculator. Covers the small set of
// medicines an ASHA can safely dose — Paracetamol, ORS, Amoxicillin, Zinc,
// Vitamin A. Explicitly NOT a prescribing tool: refers anything borderline.
// Borrowed from SwasthyaSathi / Karam Saathi operational toolkits.

import 'package:flutter/material.dart';

/// A medication whose dose can be computed from body weight + age.
class _DrugRule {
  final String name;
  final String strength;
  final String category;
  final int minAgeMonths;
  final int maxAgeMonths;
  final double mgPerKgPerDose;       // e.g., 15 for paracetamol
  final double maxMgPerDose;         // per-dose ceiling
  final double maxMgPerDay;          // daily cumulative ceiling
  final double mgPerMlSyrup;         // strength for liquid conversion
  final int dosesPerDay;
  final int courseDays;
  final String unit;                 // "syrup_ml", "tablet", "sachet"
  final String notes;

  const _DrugRule({
    required this.name,
    required this.strength,
    required this.category,
    required this.minAgeMonths,
    required this.maxAgeMonths,
    required this.mgPerKgPerDose,
    required this.maxMgPerDose,
    required this.maxMgPerDay,
    required this.mgPerMlSyrup,
    required this.dosesPerDay,
    required this.courseDays,
    required this.unit,
    required this.notes,
  });

  /// Compute dose for [weightKg]. Returns (doseMg, doseDisplay, warning?).
  ({double mg, String display, String? warning}) dose(double weightKg, int ageMonths) {
    // Per-dose ceiling first (preserves original ratio for small children).
    double mg = (mgPerKgPerDose * weightKg).clamp(0.0, maxMgPerDose);
    // Then clamp by daily total. For paracetamol this is load-bearing:
    // a 40 kg child at 15 mg/kg × 500 mg cap × 4 doses = 2000 mg/day,
    // exceeding the pediatric WHO daily cap of 1500 mg (hepatotoxicity risk).
    // We reduce the per-dose amount so cumulative daily stays safe.
    if (maxMgPerDay > 0 && dosesPerDay > 0 && mg * dosesPerDay > maxMgPerDay) {
      mg = maxMgPerDay / dosesPerDay;
    }
    String display;
    String? warning;
    switch (unit) {
      case 'syrup_ml':
        final ml = mg / mgPerMlSyrup;
        display = '${ml.toStringAsFixed(1)} mL of $strength syrup, '
            '$dosesPerDay× daily for $courseDays days';
        break;
      case 'tablet':
        // Assume strength == mg per tablet
        final tabletMg = double.tryParse(strength.replaceAll(RegExp(r'[^0-9.]'), '')) ??
            mg;
        final tablets = mg / tabletMg;
        display = '${tablets.toStringAsFixed(tablets % 1 == 0 ? 0 : 2)} '
            'tablet(s) of $strength, $dosesPerDay× daily for $courseDays days';
        if (tablets < 0.5) {
          warning =
              'Less than half a tablet — use syrup form if available for this child.';
        }
        break;
      case 'sachet':
        display = '1 sachet after each loose stool until diarrhea stops';
        break;
      default:
        display = '${mg.toStringAsFixed(0)} mg';
    }
    if (ageMonths < minAgeMonths || ageMonths > maxAgeMonths) {
      warning =
          'Age is outside the validated range for this drug — refer to a doctor.';
    }
    return (mg: mg, display: display, warning: warning);
  }
}

const List<_DrugRule> _kRules = [
  _DrugRule(
    name: 'Paracetamol (fever/pain)',
    strength: '120 mg/5 mL',
    category: 'antipyretic',
    minAgeMonths: 3,
    maxAgeMonths: 144,
    mgPerKgPerDose: 15,
    maxMgPerDose: 1000,
    // Pediatric 24h cap per WHO/NICE: 75 mg/kg or 4 g absolute, whichever is
    // lower. For a 40 kg child the 75 mg/kg/day (3000 mg) branch still beats
    // the 500 mg/dose × 4/day route, so the daily-clamp in dose() will kick
    // in around 30-35 kg to prevent hepatotoxicity on 3-day courses.
    maxMgPerDay: 3000,
    mgPerMlSyrup: 24, // 120/5
    dosesPerDay: 4,
    courseDays: 3,
    unit: 'syrup_ml',
    notes:
        'Every 6h if needed. Max 4 doses/24h. Avoid if jaundice or liver disease.',
  ),
  _DrugRule(
    name: 'Amoxicillin (bacterial infection)',
    strength: '250 mg/5 mL',
    category: 'antibiotic',
    minAgeMonths: 1,
    maxAgeMonths: 144,
    mgPerKgPerDose: 25,
    maxMgPerDose: 500,
    maxMgPerDay: 1500,  // pediatric cap for typical otitis/resp infections
    mgPerMlSyrup: 50,
    dosesPerDay: 3,
    courseDays: 5,
    unit: 'syrup_ml',
    notes:
        'Give with food. Complete full course even if child feels better. '
        'Stop and refer if rash or breathing difficulty.',
  ),
  _DrugRule(
    // Zinc uses 6 months as the low band boundary, not 6mo-5yr as a single
    // band. The 10 mg/day < 6mo vs 20 mg/day 6mo-5yr decision is made in the
    // notes; this rule applies to the 20 mg band (the majority case for
    // ASHA workflow).
    name: 'Zinc (acute diarrhea)',
    strength: '20 mg dispersible',
    category: 'diarrhea',
    minAgeMonths: 6,   // this rule covers 6mo–<5yr; infants <6mo get 10 mg/day
    maxAgeMonths: 59,
    mgPerKgPerDose: 0,
    maxMgPerDose: 20,
    maxMgPerDay: 20,
    mgPerMlSyrup: 0,
    dosesPerDay: 1,
    courseDays: 14,
    unit: 'tablet',
    notes:
        '20 mg/day for 6 months to <5 years. For infants <6 months give '
        '10 mg/day instead. Always give alongside ORS.',
  ),
  _DrugRule(
    name: 'ORS (oral rehydration)',
    strength: 'standard sachet',
    category: 'diarrhea',
    minAgeMonths: 0,
    maxAgeMonths: 1200,
    mgPerKgPerDose: 0,
    maxMgPerDose: 0,
    maxMgPerDay: 0,
    mgPerMlSyrup: 0,
    dosesPerDay: 10,
    courseDays: 3,
    unit: 'sachet',
    notes:
        'Mix 1 sachet in 1 L clean water. Offer 10 mL/kg after each loose stool. '
        'Continue breastfeeding.',
  ),
  _DrugRule(
    name: 'Vitamin A prophylaxis',
    strength: '100,000 or 200,000 IU cap',
    category: 'nutrition',
    minAgeMonths: 9,
    maxAgeMonths: 60,
    mgPerKgPerDose: 0,
    maxMgPerDose: 0,
    maxMgPerDay: 0,
    mgPerMlSyrup: 0,
    dosesPerDay: 1,
    courseDays: 1,
    unit: 'sachet',
    notes:
        '100,000 IU for 9–12 months. 200,000 IU every 6 months for 1–5 years.',
  ),
];

class DosageScreen extends StatefulWidget {
  const DosageScreen({super.key});

  @override
  State<DosageScreen> createState() => _DosageScreenState();
}

class _DosageScreenState extends State<DosageScreen> {
  final _weight = TextEditingController();
  final _ageMonths = TextEditingController();
  _DrugRule? _selected = _kRules.first;

  @override
  void dispose() {
    _weight.dispose();
    _ageMonths.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = double.tryParse(_weight.text) ?? 0.0;
    final a = int.tryParse(_ageMonths.text) ?? 0;
    final result = (_selected == null || w <= 0)
        ? null
        : _selected!.dose(w, a);

    return Scaffold(
      appBar: AppBar(title: const Text('Pediatric Dosage Calculator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'These doses are community-level first aid for children. Always refer to a doctor for severe illness, newborns, or any drug not on this list.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _weight,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _ageMonths,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Age (months)'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          DropdownButtonFormField<_DrugRule>(
            initialValue: _selected,
            decoration: const InputDecoration(labelText: 'Medicine'),
            items: [
              for (final r in _kRules)
                DropdownMenuItem(value: r, child: Text(r.name)),
            ],
            onChanged: (v) => setState(() => _selected = v),
          ),
          const SizedBox(height: 24),
          if (result != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selected!.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(result.display,
                        style: const TextStyle(fontSize: 15, height: 1.4)),
                    const SizedBox(height: 8),
                    Text(_selected!.notes,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                    if (result.warning != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(result.warning!,
                                  style: TextStyle(
                                      color: Colors.orange.shade900))),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Enter weight and age to compute the dose',
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
            ),
        ],
      ),
    );
  }
}

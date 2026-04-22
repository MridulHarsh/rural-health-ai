import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../models/patient.dart';
import 'household_service.dart';
import 'patient_history_service.dart';

class PdfExportService {
  /// Generate a patient summary PDF
  static Future<File> generateSummary(AssessmentResult result) async {
    final pdf = pw.Document();

    final riskColor = _riskColor(result.overallRisk);
    final riskText = result.overallRisk.name.toUpperCase();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // Header
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#1B8A6B'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('PATIENT HEALTH ASSESSMENT',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Rural Health AI Assistant',
                        style: const pw.TextStyle(
                            color: PdfColors.white, fontSize: 12)),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: riskColor,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(riskText,
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          // Patient Info
          _sectionHeader('Patient Information'),
          _infoRow('Name', result.patient.name),
          _infoRow('Age', '${result.patient.age} years'),
          _infoRow('Gender', result.patient.gender),
          _infoRow('Assessment Date',
              '${result.assessedAt.day}/${result.assessedAt.month}/${result.assessedAt.year}'),

          pw.SizedBox(height: 16),

          // Vitals
          _sectionHeader('Vital Signs'),
          if (result.vitals.temperature != null)
            _infoRow('Temperature', '${result.vitals.temperature}°F'),
          if (result.vitals.bloodPressure != null)
            _infoRow('Blood Pressure', result.vitals.bloodPressure!),
          if (result.vitals.heartRate != null)
            _infoRow('Heart Rate', '${result.vitals.heartRate} bpm'),
          if (result.vitals.spo2 != null)
            _infoRow('SpO2', '${result.vitals.spo2}%'),

          pw.SizedBox(height: 16),

          // Symptoms
          _sectionHeader('Reported Symptoms'),
          pw.Wrap(
            spacing: 8,
            runSpacing: 4,
            children: result.symptoms.map((s) {
              return pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#E8F5E9'),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Text(s, style: const pw.TextStyle(fontSize: 10)),
              );
            }).toList(),
          ),

          pw.SizedBox(height: 16),

          // Conditions
          _sectionHeader('Possible Conditions'),
          ...result.conditions.map((c) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(c.name,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('${(c.confidence * 100).toStringAsFixed(1)}%',
                      style: const pw.TextStyle(color: PdfColors.grey700)),
                ],
              ),
            );
          }),

          pw.SizedBox(height: 16),

          // Next Steps
          _sectionHeader('Recommended Next Steps'),
          ...result.nextSteps.asMap().entries.map((entry) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${entry.key + 1}. ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Expanded(child: pw.Text(entry.value)),
                ],
              ),
            );
          }),

          pw.SizedBox(height: 24),

          // Disclaimer
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FFF3E0'),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'DISCLAIMER: This is an AI-generated preliminary assessment and is NOT a medical diagnosis. '
              'Always consult a qualified medical professional for proper diagnosis and treatment.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.brown),
            ),
          ),
        ],
      ),
    );

    // Save to file
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/patient_${result.patient.id}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Print or share a PDF
  static Future<void> printSummary(AssessmentResult result) async {
    final file = await generateSummary(result);
    await Printing.layoutPdf(onLayout: (format) => file.readAsBytes());
  }

  static pw.Widget _sectionHeader(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(title,
          style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1B8A6B'))),
    );
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(children: [
        pw.SizedBox(
            width: 120,
            child: pw.Text('$label:',
                style: const pw.TextStyle(color: PdfColors.grey700))),
        pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ]),
    );
  }

  static PdfColor _riskColor(RiskLevel risk) {
    switch (risk) {
      case RiskLevel.emergency:
        return PdfColor.fromHex('#DC2626');
      case RiskLevel.moderate:
      case RiskLevel.urgent:
        return PdfColor.fromHex('#F59E0B');
      case RiskLevel.normal:
        return PdfColor.fromHex('#16A34A');
    }
  }

  static PdfColor _riskColorFromName(String? name) {
    switch (name) {
      case 'emergency':
        return PdfColor.fromHex('#DC2626');
      case 'urgent':
        return PdfColor.fromHex('#EA580C');
      case 'moderate':
        return PdfColor.fromHex('#F59E0B');
      case 'normal':
        return PdfColor.fromHex('#16A34A');
      default:
        return PdfColors.grey500;
    }
  }

  // ────────────────────────────────────────────────────────────
  // Household summary PDF (feature A2 — closes the loop on the
  // "Share family summary" CTA referenced in HouseholdScreen design).
  // ────────────────────────────────────────────────────────────

  /// Build a family-summary PDF listing every member, any contagion
  /// alerts, and recent visits for the given household. Self-contained:
  /// fetches members/alerts/visits via [HouseholdService] so callers only
  /// need to pass the id.
  static Future<File> generateHouseholdSummary(String householdId) async {
    final members =
        await HouseholdService.membersOfHousehold(householdId);
    final alerts =
        await HouseholdService.alertsForHousehold(householdId);
    final visits =
        await HouseholdService.visitsForHousehold(householdId);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // Header
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0EA5E9'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('HOUSEHOLD HEALTH SUMMARY',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Rural Health AI Assistant',
                        style: const pw.TextStyle(
                            color: PdfColors.white, fontSize: 12)),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    '${members.length} members · ${visits.length} visits',
                    style: pw.TextStyle(
                        color: PdfColor.fromHex('#0284C7'),
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          _sectionHeader('Household ID'),
          pw.Text(householdId,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)),

          pw.SizedBox(height: 16),

          if (alerts.isNotEmpty) ...[
            _sectionHeader('Contagion Alerts'),
            for (final a in alerts) _householdAlertRow(a),
            pw.SizedBox(height: 16),
          ],

          _sectionHeader('Members'),
          if (members.isEmpty)
            pw.Text('No members recorded.',
                style: const pw.TextStyle(color: PdfColors.grey600)),
          for (final m in members) _memberBlock(m),

          pw.SizedBox(height: 16),

          if (visits.isNotEmpty) ...[
            _sectionHeader('Recent visits'),
            ...visits.take(12).map(_visitRow),
            pw.SizedBox(height: 16),
          ],

          // Disclaimer
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FFF3E0'),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'DISCLAIMER: This summary is an AI-assisted aggregation of ASHA-worker '
              'assessments and is NOT a substitute for clinical diagnosis. All alerts '
              'require physician confirmation.',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.brown),
            ),
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final safeId = householdId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(
        '${dir.path}/household_${safeId}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Generate + launch the household-summary PDF via the system print /
  /// share sheet. Mirrors [printSummary] so the UI caller doesn't need to
  /// manage the file handle.
  static Future<void> printHouseholdSummary(String householdId) async {
    final file = await generateHouseholdSummary(householdId);
    await Printing.layoutPdf(onLayout: (format) => file.readAsBytes());
  }

  static pw.Widget _householdAlertRow(ContagionAlert a) {
    final critical = a.severity == ContagionSeverity.critical;
    final color = critical
        ? PdfColor.fromHex('#DC2626')
        : PdfColor.fromHex('#D97706');
    final bg = critical
        ? PdfColor.fromHex('#FEE2E2')
        : PdfColor.fromHex('#FEF3C7');
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                critical ? 'CRITICAL' : 'WARNING',
                style: pw.TextStyle(
                  fontSize: 9,
                  color: color,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                '${a.memberCount} members',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _humanizeAlertReason(a.reasonKey, a.trigger),
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _memberBlock(HouseholdMember m) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                m.name,
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: _riskColorFromName(m.risk),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Text(
                  (m.risk ?? 'unknown').toUpperCase(),
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Age ${m.age} · ${m.gender}${m.lastSeen != null ? ' · last seen ${_fmtDate(m.lastSeen!)}' : ''}',
            style: const pw.TextStyle(
                fontSize: 10, color: PdfColors.grey700),
          ),
          if (m.topCondition != null && m.topCondition!.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Top condition: ${m.topCondition}',
                style: const pw.TextStyle(fontSize: 10)),
          ],
          if (m.symptoms.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Symptoms: ${m.symptoms.take(5).join(', ')}',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey800)),
          ],
        ],
      ),
    );
  }

  static pw.Widget _visitRow(Map<String, dynamic> v) {
    final dt = DateTime.tryParse(v['createdAt']?.toString() ?? '');
    final conditions = (v['conditions'] as List?) ?? const [];
    final topName = conditions.isNotEmpty && conditions.first is Map
        ? (conditions.first as Map)['name']?.toString()
        : null;
    final riskColor = _riskColorFromName(v['overallRisk']?.toString());
    final name = (v['patientName']?.toString().isNotEmpty ?? false)
        ? v['patientName'].toString()
        : 'Unknown';
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8FAFC'),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 4,
            height: 14,
            decoration: pw.BoxDecoration(
              color: riskColor,
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              '$name — ${topName ?? 'No conditions'}',
              style: const pw.TextStyle(fontSize: 10),
              maxLines: 1,
            ),
          ),
          if (dt != null)
            pw.Text(
              _fmtDate(dt),
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600),
            ),
        ],
      ),
    );
  }

  static String _humanizeAlertReason(String key, String trigger) {
    // Mirrors the translation keys from AppTranslations but baked in
    // English for the PDF — the PDF is a PHC-facing artifact and should
    // stay in English regardless of the ASHA's display language.
    switch (key) {
      case 'household_alert_shared_contagious':
        return 'Shared contagious condition: $trigger';
      case 'household_alert_febrile_cluster':
        return 'Febrile cluster — multiple members with fever';
      case 'household_alert_enteric_cluster':
        return 'Enteric cluster — diarrhoea/vomiting among members';
      case 'household_alert_respiratory_cluster':
        return 'Respiratory cluster — cough/breathlessness among members';
      default:
        return key;
    }
  }

  static String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  // ────────────────────────────────────────────────────────────
  // Patient timeline PDF (feature A3)
  // ────────────────────────────────────────────────────────────

  /// Build a longitudinal timeline PDF for one patient — visit log with
  /// vitals columns so trends are readable without a chart image. A
  /// table beats a rasterized chart because it stays searchable and
  /// keeps the PDF tiny (~20 kB rather than ~200 kB).
  static Future<File> generateTimeline(PatientTimeline timeline) async {
    final pdf = pw.Document();
    final ident = timeline.identity;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#14B8A6'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('PATIENT TIMELINE',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Rural Health AI Assistant',
                        style: const pw.TextStyle(
                            color: PdfColors.white, fontSize: 12)),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    '${timeline.visits.length} visits',
                    style: pw.TextStyle(
                        color: PdfColor.fromHex('#0E7C77'),
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          _sectionHeader('Patient'),
          _infoRow('Name', ident.displayName),
          _infoRow('Age (latest)', '${ident.latestAge}'),
          _infoRow('Gender', ident.gender.isEmpty ? '-' : ident.gender),
          if (ident.abhaId != null)
            _infoRow('ABHA ID', ident.abhaId!),
          if (ident.isApproximate) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Note: identity matched by name + age (no ABHA ID). '
              'Visits with typo-variant names may be split across lanes.',
              style: pw.TextStyle(
                  fontSize: 9,
                  color: PdfColor.fromHex('#B45309'),
                  fontStyle: pw.FontStyle.italic),
            ),
          ],

          pw.SizedBox(height: 16),

          if (timeline.vitalsSeries.length >= 2) ...[
            _sectionHeader('Vitals trend'),
            _vitalsTable(timeline),
            pw.SizedBox(height: 16),
          ],

          _sectionHeader('Visits (newest first)'),
          for (final v in timeline.visits) _timelineVisitBlock(v),

          pw.SizedBox(height: 24),

          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FFF3E0'),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'DISCLAIMER: This timeline is an AI-assisted aggregation of ASHA-worker '
              'assessments and is NOT a substitute for a physician-reviewed medical '
              'record. Interpret trends in context.',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.brown),
            ),
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final safeKey =
        ident.key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(
        '${dir.path}/timeline_${safeKey}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Future<void> printTimeline(PatientTimeline timeline) async {
    final file = await generateTimeline(timeline);
    await Printing.layoutPdf(onLayout: (format) => file.readAsBytes());
  }

  static pw.Widget _vitalsTable(PatientTimeline timeline) {
    final points = timeline.vitalsSeries;
    return pw.TableHelper.fromTextArray(
      headers: const ['Date', 'Temp (°F)', 'BP', 'HR', 'SpO₂', 'Weight'],
      data: [
        for (final p in points)
          [
            _fmtDate(p.at),
            _fmtNum(p.temperature),
            p.systolic != null && p.diastolic != null
                ? '${p.systolic!.round()}/${p.diastolic!.round()}'
                : '-',
            _fmtNum(p.heartRate),
            _fmtNum(p.spo2),
            _fmtNum(p.weight),
          ],
      ],
      border: pw.TableBorder.all(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration:
          pw.BoxDecoration(color: PdfColor.fromHex('#14B8A6')),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    );
  }

  static String _fmtNum(double? v) {
    if (v == null) return '-';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  static pw.Widget _timelineVisitBlock(Map<String, dynamic> v) {
    final dt = DateTime.tryParse(v['createdAt']?.toString() ?? '');
    final conds = (v['conditions'] as List?) ?? const [];
    final top = conds.isNotEmpty && conds.first is Map
        ? (conds.first as Map)['name']?.toString()
        : null;
    final syms = <String>[
      for (final s in (v['symptoms'] as List? ?? const []))
        if (s is String) s,
    ];
    final risk = v['overallRisk']?.toString();
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                dt != null ? _fmtDate(dt) : '-',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: _riskColorFromName(risk),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Text(
                  (risk ?? 'unknown').toUpperCase(),
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          if (top != null) ...[
            pw.SizedBox(height: 4),
            pw.Text('Top: $top',
                style: const pw.TextStyle(fontSize: 10)),
          ],
          if (syms.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Symptoms: ${syms.take(6).join(', ')}',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey800)),
          ],
        ],
      ),
    );
  }
}

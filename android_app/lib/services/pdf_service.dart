import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../models/patient.dart';

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
}

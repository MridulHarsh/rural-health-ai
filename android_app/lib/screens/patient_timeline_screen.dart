// patient_timeline_screen.dart
// Longitudinal view of one patient across all visits. Shows a vertical
// visit timeline + a toggleable vitals sparkline (temp / systolic / HR /
// SpO₂) so the ASHA can spot trends like a slowly-rising blood pressure or
// a child losing weight that wouldn't show in a single assessment.
//
// Feature #6 in the NeuCure roadmap.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/translations.dart';
import '../models/patient_identity.dart';
import '../services/patient_history_service.dart';
import '../services/pdf_service.dart';

enum _VitalChoice { temperature, systolic, heartRate, spo2 }

class PatientTimelineScreen extends StatefulWidget {
  final PatientIdentity identity;

  const PatientTimelineScreen({super.key, required this.identity});

  @override
  State<PatientTimelineScreen> createState() => _PatientTimelineScreenState();
}

class _PatientTimelineScreenState extends State<PatientTimelineScreen> {
  PatientTimeline? _timeline;
  bool _loading = true;
  String _lang = 'en';
  _VitalChoice _chart = _VitalChoice.temperature;

  String _t(String key) => AppTranslations.t(key, _lang);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final t = await PatientHistoryService.timelineFor(widget.identity);
    if (!mounted) return;
    setState(() {
      _lang = prefs.getString('language') ?? 'en';
      _timeline = t;
      _loading = false;
    });
  }

  Color _riskColor(String? risk) {
    switch (risk) {
      case 'emergency':
        return const Color(0xFFDC2626);
      case 'urgent':
        return const Color(0xFFEA580C);
      case 'moderate':
        return const Color(0xFFF59E0B);
      case 'normal':
        return const Color(0xFF16A34A);
      default:
        return Colors.grey;
    }
  }

  Future<void> _exportPdf() async {
    final t = _timeline;
    if (t == null) return;
    try {
      await PdfExportService.printTimeline(t);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('pdf_export_failed')}: ${e.runtimeType}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('patient_timeline')),
        actions: [
          if (!_loading && _timeline != null && _timeline!.visits.isNotEmpty)
            IconButton(
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              tooltip: _t('timeline_export'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _timeline == null || _timeline!.visits.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildHeader(_timeline!),
                      const SizedBox(height: 16),
                      _buildChartSection(_timeline!),
                      const SizedBox(height: 20),
                      Text(
                        '${_t('visits')} (${_timeline!.visits.length})',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final v in _timeline!.visits) _buildVisitTile(v),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _exportPdf,
                        icon: const Icon(Icons.picture_as_pdf_rounded,
                            size: 18),
                        label: Text(_t('timeline_export')),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timeline_rounded,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(_t('timeline_empty'),
              style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildHeader(PatientTimeline t) {
    final ident = t.identity;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14B8A6), Color(0xFF0E7C77)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ident.displayName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${ident.latestAge} · ${ident.gender.isEmpty ? '-' : ident.gender}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${t.visits.length} ${_t('visits')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (ident.isApproximate) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _t('timeline_approx_match_warning'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartSection(PatientTimeline t) {
    if (t.vitalsSeries.length < 2) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _t('timeline_chart_need_more_visits'),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      );
    }
    final points = t.vitalsSeries;
    final chartData = _chartPoints(points);
    final nonNull = chartData.where((s) => s.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('timeline_vitals_trend'),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chartChip(_VitalChoice.temperature, _t('temperature_short')),
              _chartChip(_VitalChoice.systolic, _t('bp_short')),
              _chartChip(_VitalChoice.heartRate, _t('heart_rate_short')),
              _chartChip(_VitalChoice.spo2, _t('spo2_short')),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            child: nonNull.isEmpty
                ? Center(
                    child: Text(
                      _t('timeline_chart_no_data'),
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(
                        show: true,
                        drawVerticalLine: false,
                      ),
                      titlesData: const FlTitlesData(
                        show: true,
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(
                            color: Colors.grey.shade200, width: 1),
                      ),
                      lineBarsData: [
                        for (final series in nonNull)
                          LineChartBarData(
                            spots: series,
                            isCurved: false,
                            color: const Color(0xFF14B8A6),
                            barWidth: 2,
                            dotData: const FlDotData(show: true),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chartChip(_VitalChoice choice, String label) {
    final selected = _chart == choice;
    return GestureDetector(
      onTap: () => setState(() => _chart = choice),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF14B8A6)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade700,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Build chart series. Returns a list with one entry (the active vital) to
  /// keep the chart single-lined; could be extended to overlay multiple if
  /// useful later.
  List<List<FlSpot>> _chartPoints(List<VitalsPoint> points) {
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final y = _pickValue(p);
      if (y == null) continue;
      spots.add(FlSpot(i.toDouble(), y));
    }
    return [spots];
  }

  double? _pickValue(VitalsPoint p) {
    switch (_chart) {
      case _VitalChoice.temperature:
        return p.temperature;
      case _VitalChoice.systolic:
        return p.systolic;
      case _VitalChoice.heartRate:
        return p.heartRate;
      case _VitalChoice.spo2:
        return p.spo2;
    }
  }

  Widget _buildVisitTile(Map<String, dynamic> v) {
    final dt = DateTime.tryParse(v['createdAt']?.toString() ?? '');
    final rc = _riskColor(v['overallRisk']?.toString());
    final conditions = (v['conditions'] as List?) ?? const [];
    final topName = conditions.isNotEmpty && conditions.first is Map
        ? (conditions.first as Map)['name']?.toString()
        : null;
    final symptoms = <String>[
      for (final s in (v['symptoms'] as List? ?? const []))
        if (s is String) s,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 6,
              height: 52,
              decoration: BoxDecoration(
                color: rc,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: rc.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          (v['overallRisk']?.toString() ?? 'unknown')
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: rc,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (dt != null)
                        Text(
                          '${dt.day}/${dt.month}/${dt.year}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (topName != null)
                    Text(
                      topName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  if (symptoms.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      symptoms.take(4).map((s) => _t(s)).join(' · '),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// household_screen.dart
// Per-household detail view — the screen the ASHA opens when a household has
// an active contagion cluster or she wants to review a family's case mix.
// Shows unique members (one card per person), recent visits, and any
// contagion alerts raised by [HouseholdService].
//
// Feature #5 in the NeuCure roadmap.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/translations.dart';
import '../services/household_service.dart';
import '../services/pdf_service.dart';

class HouseholdScreen extends StatefulWidget {
  final String householdId;

  const HouseholdScreen({super.key, required this.householdId});

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  List<HouseholdMember> _members = const [];
  List<ContagionAlert> _alerts = const [];
  List<Map<String, dynamic>> _visits = const [];
  bool _loading = true;
  String _lang = 'en';

  String _t(String key) => AppTranslations.t(key, _lang);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final members =
        await HouseholdService.membersOfHousehold(widget.householdId);
    final alerts =
        await HouseholdService.alertsForHousehold(widget.householdId);
    final visits =
        await HouseholdService.visitsForHousehold(widget.householdId);
    if (!mounted) return;
    setState(() {
      _lang = prefs.getString('language') ?? 'en';
      _members = members;
      _alerts = alerts;
      _visits = visits;
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
    try {
      await PdfExportService.printHouseholdSummary(widget.householdId);
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
        title: Text(_t('household_view')),
        actions: [
          if (!_loading && _members.isNotEmpty)
            IconButton(
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              tooltip: _t('household_share_summary'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  if (_alerts.isNotEmpty) ...[
                    _buildAlertsSection(),
                    const SizedBox(height: 16),
                  ],
                  _buildMembersSection(),
                  const SizedBox(height: 20),
                  _buildVisitsSection(),
                  if (_members.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf_rounded,
                          size: 18),
                      label: Text(_t('household_share_summary')),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0EA5E9), Color(0xFF0284C7)],
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
                child: const Icon(Icons.groups_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.householdId,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_members.length} ${_t('members')} · ${_visits.length} ${_t('visits')}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('household_contagion_alerts'),
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final alert in _alerts) _buildAlertCard(alert),
      ],
    );
  }

  Widget _buildAlertCard(ContagionAlert alert) {
    final critical = alert.severity == ContagionSeverity.critical;
    final color = critical
        ? const Color(0xFFDC2626)
        : const Color(0xFFD97706);
    final bg = critical
        ? const Color(0xFFFEE2E2)
        : const Color(0xFFFEF3C7);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  critical
                      ? Icons.warning_rounded
                      : Icons.info_outline_rounded,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t(alert.reasonKey),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: color,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${alert.memberCount}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_t('trigger')}: ${_t(alert.trigger)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 6),
            Text(
              _t(alert.actionKey),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade900,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersSection() {
    if (_members.isEmpty) {
      return Text(
        _t('household_no_members'),
        style: TextStyle(color: Colors.grey.shade500),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('household_members'),
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final m in _members) _buildMemberCard(m),
      ],
    );
  }

  Widget _buildMemberCard(HouseholdMember m) {
    final rc = _riskColor(m.risk);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: rc.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    (m.risk ?? 'unknown').toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: rc,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const Spacer(),
                if (m.lastSeen != null)
                  Text(
                    '${m.lastSeen!.day}/${m.lastSeen!.month}/${m.lastSeen!.year}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              m.name,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${_t('age')}: ${m.age} · ${m.gender}',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (m.topCondition != null && m.topCondition!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                m.topCondition!,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
            if (m.symptoms.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: m.symptoms.take(4).map((s) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _t(s),
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVisitsSection() {
    if (_visits.length <= _members.length) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('household_recent_visits'),
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final v in _visits.take(8)) _buildVisitRow(v),
      ],
    );
  }

  Widget _buildVisitRow(Map<String, dynamic> v) {
    final dt = DateTime.tryParse(v['createdAt']?.toString() ?? '');
    final rc = _riskColor(v['overallRisk']?.toString());
    final conditions = (v['conditions'] as List?) ?? const [];
    final top = conditions.isNotEmpty && conditions.first is Map
        ? (conditions.first as Map)['name']?.toString()
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 24,
              decoration: BoxDecoration(
                color: rc,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (v['patientName']?.toString().isNotEmpty ?? false)
                        ? v['patientName'].toString()
                        : 'Unknown',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if (top != null)
                    Text(
                      top,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
            if (dt != null)
              Text(
                '${dt.day}/${dt.month}',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500),
              ),
          ],
        ),
      ),
    );
  }
}

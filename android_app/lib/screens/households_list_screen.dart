// households_list_screen.dart
// Lists every distinct household the ASHA has seen, sorted by active
// contagion-alert count then by most-recent visit. Tapping a row opens
// [HouseholdScreen] for the per-household detail view.
//
// Feature #5 in the NeuCure roadmap (household contagion cluster view).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/translations.dart';
import '../services/household_service.dart';
import 'household_screen.dart';

class HouseholdsListScreen extends StatefulWidget {
  const HouseholdsListScreen({super.key});

  @override
  State<HouseholdsListScreen> createState() => _HouseholdsListScreenState();
}

class _HouseholdsListScreenState extends State<HouseholdsListScreen> {
  List<HouseholdSummary> _households = const [];
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
    final list = await HouseholdService.listHouseholds();
    if (!mounted) return;
    setState(() {
      _lang = prefs.getString('language') ?? 'en';
      _households = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('households'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _households.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _households.length,
                  itemBuilder: (context, i) => _HouseholdTile(
                    summary: _households[i],
                    lang: _lang,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HouseholdScreen(
                            householdId: _households[i].householdId,
                          ),
                        ),
                      );
                      _load();
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.groups_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(_t('households_empty'),
              style:
                  TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _t('households_empty_body'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _HouseholdTile extends StatelessWidget {
  final HouseholdSummary summary;
  final String lang;
  final VoidCallback onTap;

  const _HouseholdTile({
    required this.summary,
    required this.lang,
    required this.onTap,
  });

  String _t(String key) => AppTranslations.t(key, lang);

  @override
  Widget build(BuildContext context) {
    final hasAlerts = summary.alertCount > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasAlerts
                  ? const Color(0xFFDC2626).withValues(alpha: 0.35)
                  : Colors.grey.shade200,
              width: hasAlerts ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (hasAlerts
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF0EA5E9))
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.groups_rounded,
                      color: hasAlerts
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF0EA5E9),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.householdId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${summary.memberCount} ${_t('members')} · ${summary.visitCount} ${_t('visits')}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  if (hasAlerts)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 12, color: Color(0xFFDC2626)),
                          const SizedBox(width: 4),
                          Text(
                            '${summary.alertCount}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (summary.lastVisit != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${_t('last_visit')}: ${summary.lastVisit!.day}/${summary.lastVisit!.month}/${summary.lastVisit!.year}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

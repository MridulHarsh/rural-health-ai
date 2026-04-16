import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/translations.dart';
import '../services/ml_service.dart';
import '../services/database_service.dart';

class HomeScreen extends StatefulWidget {
  final MLService mlService;

  const HomeScreen({super.key, required this.mlService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lang = 'en';
  int _recordCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final count = await DatabaseService.getCount();
    if (!mounted) return;
    setState(() {
      _lang = prefs.getString('language') ?? 'en';
      _recordCount = count;
    });
  }

  String _t(String key) => AppTranslations.t(key, _lang);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ── Top Bar ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.health_and_safety_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_t('app_name'),
                                style: Theme.of(context).textTheme.titleLarge),
                            Text(
                              _t('offline_ready'),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    ),
                    // Language + Settings
                    Row(
                      children: [
                        _buildLangButton(context),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () async {
                            await Navigator.pushNamed(context, '/settings');
                            _loadPrefs();
                          },
                          icon: const Icon(Icons.settings_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                          ),
                        ),
                      ],
                    ),
                  ],
                ).animate().fadeIn(duration: 400.ms),

                const SizedBox(height: 32),

                // ── Hero Card ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                        const Color(0xFF14B8A6),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.medical_services_rounded,
                          color: Colors.white, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        _t('tagline'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            await Navigator.pushNamed(context, '/assessment');
                            _loadPrefs();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Theme.of(context).colorScheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_circle_outline_rounded, size: 22),
                              const SizedBox(width: 10),
                              Text(
                                _t('new_assessment'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().slideY(begin: 0.1, duration: 500.ms).fadeIn(),

                const SizedBox(height: 28),

                // ── Quick Stats ──
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.people_alt_rounded,
                        label: _t('patient_history'),
                        value: '$_recordCount',
                        color: const Color(0xFF6366F1),
                        onTap: () async {
                          await Navigator.pushNamed(context, '/history');
                          _loadPrefs();
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.offline_bolt_rounded,
                        label: 'AI Model',
                        value: widget.mlService.isInitialized ? 'Ready' : 'Fallback',
                        color: widget.mlService.isInitialized
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFF59E0B),
                        onTap: null,
                      ),
                    ),
                  ],
                ).animate().slideY(begin: 0.1, duration: 500.ms, delay: 100.ms).fadeIn(),

                const SizedBox(height: 28),

                // ── Feature Cards ──
                Text(
                  'Input Modes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),

                _FeatureCard(
                  icon: Icons.edit_note_rounded,
                  title: _t('symptoms'),
                  subtitle: _t('enter_symptoms'),
                  color: const Color(0xFF1B8A6B),
                  delay: 200,
                  onTap: () async {
                    await Navigator.pushNamed(context, '/assessment');
                    _loadPrefs();
                  },
                ),
                _FeatureCard(
                  icon: Icons.mic_rounded,
                  title: _t('voice_input'),
                  subtitle: _t('tap_to_speak'),
                  color: const Color(0xFF6366F1),
                  delay: 300,
                  onTap: () async {
                    await Navigator.pushNamed(context, '/assessment');
                    _loadPrefs();
                  },
                ),
                _FeatureCard(
                  icon: Icons.camera_alt_rounded,
                  title: _t('camera_input'),
                  subtitle: _t('take_photo'),
                  color: const Color(0xFFF59E0B),
                  delay: 400,
                  onTap: () async {
                    await Navigator.pushNamed(context, '/assessment');
                    _loadPrefs();
                  },
                ),

                const SizedBox(height: 20),

                // ── Disclaimer ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: Colors.amber.shade700, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _t('disclaimer'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 500.ms),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLangButton(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (code) {
        setState(() => _lang = code);
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('language', code);
        });
      },
      itemBuilder: (context) {
        return AppTranslations.languageNames.entries.map((entry) {
          return PopupMenuItem(
            value: entry.key,
            child: Row(
              children: [
                if (entry.key == _lang)
                  const Icon(Icons.check, size: 16, color: Color(0xFF1B8A6B)),
                if (entry.key == _lang) const SizedBox(width: 8),
                Text(entry.value),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 18),
            const SizedBox(width: 4),
            Text(
              AppTranslations.languageNames[_lang] ?? 'EN',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final int delay;
  final VoidCallback? onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.delay = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    ).animate().slideX(begin: 0.05, duration: 400.ms, delay: delay.ms).fadeIn();
  }
}

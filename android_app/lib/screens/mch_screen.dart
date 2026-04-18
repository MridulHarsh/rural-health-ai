// mch_screen.dart
// Maternal & Child Health tracker redesigned for ASHA-friendly workflow:
//  - Three tabs (Upcoming, Patients, Done) so items aren't scattered.
//  - Upcoming tab shows overdue/due-this-week/upcoming in colored sections.
//  - Patients tab groups all records by person — one row per ANC course or
//    child, with a compact completion bar and a "next up" pointer.
//  - Each item has an obvious checkbox (tap = toggle complete/incomplete).
//  - Swipe-right to mark done, swipe-left to delete.

import 'package:flutter/material.dart';

import '../services/mch_service.dart';

class MchScreen extends StatefulWidget {
  const MchScreen({super.key});

  @override
  State<MchScreen> createState() => _MchScreenState();
}

class _MchScreenState extends State<MchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<MchRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await MchService.all();
    if (!mounted) return;
    setState(() {
      _records = r;
      _loading = false;
    });
  }

  Future<void> _toggle(MchRecord r) async {
    if (r.id == null) return;
    if (r.completed) {
      // Un-complete: delete and recreate as pending (service has no "un-mark")
      await MchService.delete(r.id!);
      await MchService.insertBatch([
        MchRecord(
          patientName: r.patientName,
          patientAge: r.patientAge,
          kind: r.kind,
          label: r.label,
          dueDate: r.dueDate,
        )
      ]);
    } else {
      await MchService.markComplete(r.id!);
    }
    await _load();
  }

  Future<void> _delete(MchRecord r) async {
    if (r.id == null) return;
    await MchService.delete(r.id!);
    await _load();
  }

  Future<void> _addAnc() async {
    final res = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AncSheet(),
    );
    if (res == null) return;
    final visits = MchService.scheduleAnc(
      patientName: res['name'] as String,
      patientAge: res['age'] as int?,
      lmp: res['lmp'] as DateTime,
    );
    await MchService.insertBatch(visits);
    await _load();
  }

  Future<void> _addImmunization() async {
    final res = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ImmunizationSheet(),
    );
    if (res == null) return;
    final records = MchService.scheduleImmunizations(
      patientName: res['name'] as String,
      birthDate: res['dob'] as DateTime,
    );
    await MchService.insertBatch(records);
    await _load();
  }

  Future<void> _showAddMenu() async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.pregnant_woman_rounded),
              title: const Text('Schedule ANC visits'),
              subtitle: const Text('4 visits from LMP date'),
              onTap: () {
                Navigator.pop(ctx);
                _addAnc();
              },
            ),
            ListTile(
              leading: const Icon(Icons.vaccines_rounded),
              title: const Text('Schedule immunizations'),
              subtitle: const Text('UIP schedule from date of birth'),
              onTap: () {
                Navigator.pop(ctx);
                _addImmunization();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maternal & Child Health'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.event_available_rounded), text: 'Upcoming'),
            Tab(icon: Icon(Icons.groups_rounded), text: 'Patients'),
            Tab(icon: Icon(Icons.task_alt_rounded), text: 'Done'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMenu,
        icon: const Icon(Icons.add),
        label: const Text('Schedule'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildUpcomingTab(),
                _buildPatientsTab(),
                _buildDoneTab(),
              ],
            ),
    );
  }

  // ── TAB 1: Upcoming (overdue → due-soon → later) ──────────────────────
  Widget _buildUpcomingTab() {
    final pending = _records.where((r) => !r.completed).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (pending.isEmpty) return _emptyState('No upcoming visits scheduled.');

    final overdue = pending.where((r) => r.isOverdue).toList();
    final dueSoon = pending.where((r) => r.isDueSoon).toList();
    final later = pending
        .where((r) => !r.isOverdue && !r.isDueSoon)
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (overdue.isNotEmpty)
            _UrgencySection(
              title: 'Overdue',
              color: Colors.red,
              icon: Icons.warning_rounded,
              records: overdue,
              onToggle: _toggle,
              onDelete: _delete,
            ),
          if (dueSoon.isNotEmpty)
            _UrgencySection(
              title: 'Due this week',
              color: Colors.orange,
              icon: Icons.schedule_rounded,
              records: dueSoon,
              onToggle: _toggle,
              onDelete: _delete,
            ),
          if (later.isNotEmpty)
            _UrgencySection(
              title: 'Later',
              color: Colors.blue,
              icon: Icons.event_note_rounded,
              records: later,
              onToggle: _toggle,
              onDelete: _delete,
            ),
        ],
      ),
    );
  }

  // ── TAB 2: Patients (grouped by patient, progress bar per group) ──────
  Widget _buildPatientsTab() {
    if (_records.isEmpty) {
      return _emptyState('No patients scheduled yet.');
    }
    // Group by (patientName + kind) — a mother's ANC and her child's
    // immunizations are separate "courses".
    final groups = <String, List<MchRecord>>{};
    for (final r in _records) {
      final key = '${r.patientName}||${r.kind.name}';
      groups.putIfAbsent(key, () => []).add(r);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => a.split('||').first.compareTo(b.split('||').first));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: keys.length,
        itemBuilder: (ctx, i) {
          final key = keys[i];
          final items = groups[key]!
            ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
          final parts = key.split('||');
          final patient = parts[0];
          final kind = MchKind.values.firstWhere((k) => k.name == parts[1]);
          return _PatientGroupCard(
            patientName: patient,
            kind: kind,
            records: items,
            onToggle: _toggle,
            onDelete: _delete,
          );
        },
      ),
    );
  }

  // ── TAB 3: Done (simple log) ──────────────────────────────────────────
  Widget _buildDoneTab() {
    final done = _records.where((r) => r.completed).toList()
      ..sort((a, b) => (b.completedOn ?? b.dueDate)
          .compareTo(a.completedOn ?? a.dueDate));
    if (done.isEmpty) return _emptyState('No completed visits yet.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: done.length,
        itemBuilder: (_, i) => _MchTile(
          record: done[i],
          onToggle: _toggle,
          onDelete: _delete,
        ),
      ),
    );
  }

  Widget _emptyState(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_rounded,
                  size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Text(
                'Tap "Schedule" below to add a patient.',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
}

/// Colored section header + the list of records under it.
class _UrgencySection extends StatelessWidget {
  final String title;
  final MaterialColor color;
  final IconData icon;
  final List<MchRecord> records;
  final Future<void> Function(MchRecord) onToggle;
  final Future<void> Function(MchRecord) onDelete;

  const _UrgencySection({
    required this.title,
    required this.color,
    required this.icon,
    required this.records,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.shade200),
          ),
          child: Row(children: [
            Icon(icon, color: color.shade700, size: 18),
            const SizedBox(width: 8),
            Text(
              '$title  (${records.length})',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color.shade900,
              ),
            ),
          ]),
        ),
        ...records.map((r) => _MchTile(
              record: r,
              accent: color,
              onToggle: onToggle,
              onDelete: onDelete,
            )),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Single patient's full schedule in one card with a progress bar.
class _PatientGroupCard extends StatefulWidget {
  final String patientName;
  final MchKind kind;
  final List<MchRecord> records;
  final Future<void> Function(MchRecord) onToggle;
  final Future<void> Function(MchRecord) onDelete;

  const _PatientGroupCard({
    required this.patientName,
    required this.kind,
    required this.records,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<_PatientGroupCard> createState() => _PatientGroupCardState();
}

class _PatientGroupCardState extends State<_PatientGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final done = widget.records.where((r) => r.completed).length;
    final total = widget.records.length;
    final nextUp = widget.records.firstWhere(
      (r) => !r.completed,
      orElse: () => widget.records.last,
    );
    final isAllDone = done == total;
    final accent = widget.kind == MchKind.anc
        ? Colors.pink
        : Colors.teal;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            leading: CircleAvatar(
              backgroundColor: accent.shade50,
              child: Icon(
                widget.kind == MchKind.anc
                    ? Icons.pregnant_woman_rounded
                    : Icons.vaccines_rounded,
                color: accent.shade700,
              ),
            ),
            title: Text(widget.patientName,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  widget.kind == MchKind.anc
                      ? 'ANC course — $done / $total visits done'
                      : 'Immunization schedule — $done / $total shots done',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 5,
                    backgroundColor: Colors.grey.shade200,
                    color: isAllDone ? Colors.green : accent.shade400,
                  ),
                ),
                if (!isAllDone) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Next: ${nextUp.label} — due ${_fmt(nextUp.dueDate)}',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
            trailing: Icon(_expanded
                ? Icons.expand_less_rounded
                : Icons.expand_more_rounded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ...widget.records.map((r) => _MchTile(
                  record: r,
                  compact: true,
                  onToggle: widget.onToggle,
                  onDelete: widget.onDelete,
                )),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

/// Single row with a checkbox, swipe-to-delete, and date/patient info.
class _MchTile extends StatelessWidget {
  final MchRecord record;
  final MaterialColor? accent;
  final bool compact;
  final Future<void> Function(MchRecord) onToggle;
  final Future<void> Function(MchRecord) onDelete;

  const _MchTile({
    required this.record,
    required this.onToggle,
    required this.onDelete,
    this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = record;
    final dateStr = '${r.dueDate.day}/${r.dueDate.month}/${r.dueDate.year}';
    final completedStr = r.completedOn != null
        ? ' — done ${r.completedOn!.day}/${r.completedOn!.month}'
        : '';
    final tile = CheckboxListTile(
      contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 12, vertical: compact ? 0 : 2),
      controlAffinity: ListTileControlAffinity.leading,
      value: r.completed,
      onChanged: (_) => onToggle(r),
      title: Text(
        r.label,
        style: TextStyle(
          fontWeight: compact ? FontWeight.normal : FontWeight.w600,
          decoration: r.completed ? TextDecoration.lineThrough : null,
          color: r.completed ? Colors.grey.shade600 : null,
        ),
      ),
      subtitle: Text(
        compact
            ? 'Due $dateStr$completedStr'
            : '${r.patientName} • Due $dateStr$completedStr',
        style: const TextStyle(fontSize: 12),
      ),
      secondary: compact
          ? null
          : Icon(
              r.kind == MchKind.anc
                  ? Icons.pregnant_woman_rounded
                  : Icons.vaccines_rounded,
              color: accent?.shade600 ?? Colors.grey.shade500,
            ),
    );
    // Swipe-left to delete; the checkbox handles mark/unmark directly so we
    // don't need a swipe-right gesture (avoids accidental completion).
    return Dismissible(
      key: ValueKey('mch_${r.id ?? r.hashCode}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete this visit?'),
                content: Text(r.label),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete')),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onDelete(r),
      child: compact
          ? tile
          : Card(
              margin: const EdgeInsets.only(bottom: 6),
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: tile,
            ),
    );
  }
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ── Input sheets (same as before, unchanged) ───────────────────────────
class _AncSheet extends StatefulWidget {
  const _AncSheet();
  @override
  State<_AncSheet> createState() => _AncSheetState();
}

class _AncSheetState extends State<_AncSheet> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  DateTime? _lmp;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Schedule ANC visits',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
              controller: _name,
              decoration:
                  const InputDecoration(labelText: 'Mother\'s name')),
          const SizedBox(height: 8),
          TextField(
              controller: _age,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Age (years)')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(_lmp == null
                ? 'Pick last menstrual period (LMP)'
                : 'LMP: ${_fmt(_lmp!)} — EDD ${_fmt(MchService.eddFromLmp(_lmp!))}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _lmp ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 300)),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _lmp = picked);
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_name.text.trim().isEmpty || _lmp == null) return;
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'age': int.tryParse(_age.text),
                'lmp': _lmp,
              });
            },
            child: const Text('Create 4-visit schedule'),
          ),
        ],
      ),
    );
  }
}

class _ImmunizationSheet extends StatefulWidget {
  const _ImmunizationSheet();
  @override
  State<_ImmunizationSheet> createState() => _ImmunizationSheetState();
}

class _ImmunizationSheetState extends State<_ImmunizationSheet> {
  final _name = TextEditingController();
  DateTime? _dob;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Schedule child immunizations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Child\'s name')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(_dob == null
                ? 'Pick date of birth'
                : 'DOB: ${_fmt(_dob!)}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _dob ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _dob = picked);
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_name.text.trim().isEmpty || _dob == null) return;
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'dob': _dob,
              });
            },
            child: const Text('Create UIP schedule'),
          ),
        ],
      ),
    );
  }
}

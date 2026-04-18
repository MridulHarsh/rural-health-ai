// mch_screen.dart
// Maternal & Child Health tracker: schedule ANC + immunizations from LMP or
// birth date, view upcoming/overdue items, mark complete.

import 'package:flutter/material.dart';

import '../services/mch_service.dart';

class MchScreen extends StatefulWidget {
  const MchScreen({super.key});

  @override
  State<MchScreen> createState() => _MchScreenState();
}

class _MchScreenState extends State<MchScreen> {
  List<MchRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await MchService.all();
    if (!mounted) return;
    setState(() {
      _records = r;
      _loading = false;
    });
  }

  Future<void> _markDone(MchRecord r) async {
    if (r.id == null) return;
    await MchService.markComplete(r.id!);
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

  @override
  Widget build(BuildContext context) {
    final overdue =
        _records.where((r) => r.isOverdue && !r.completed).toList();
    final dueSoon =
        _records.where((r) => r.isDueSoon && !r.completed).toList();
    final upcoming = _records
        .where((r) =>
            !r.completed &&
            !r.isOverdue &&
            !r.isDueSoon)
        .toList();
    final completed = _records.where((r) => r.completed).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Maternal & Child Health')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'fab_anc',
            onPressed: _addAnc,
            icon: const Icon(Icons.pregnant_woman),
            label: const Text('New ANC'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'fab_imm',
            onPressed: _addImmunization,
            icon: const Icon(Icons.vaccines),
            label: const Text('New Immunization'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (overdue.isNotEmpty)
                  _section('Overdue', Colors.red, overdue),
                if (dueSoon.isNotEmpty)
                  _section('Due this week', Colors.orange, dueSoon),
                if (upcoming.isNotEmpty)
                  _section('Upcoming', Colors.blueGrey, upcoming),
                if (completed.isNotEmpty)
                  _section('Completed', Colors.green, completed,
                      collapsed: true),
                if (_records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No records yet. Tap a button below to schedule ANC visits or immunizations.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _section(
    String title,
    MaterialColor color,
    List<MchRecord> rs, {
    bool collapsed = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color.shade500,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$title  (${rs.length})',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color.shade800,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          if (!collapsed)
            ...rs.map((r) => _card(r, color))
          else
            ExpansionTile(
              title: Text('${rs.length} completed',
                  style: TextStyle(color: color.shade700)),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              children: rs.map((r) => _card(r, color)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _card(MchRecord r, MaterialColor color) {
    final d = r.dueDate;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(
          r.kind == MchKind.anc ? Icons.pregnant_woman : Icons.vaccines,
          color: color.shade600,
        ),
        title: Text(r.label,
            style: TextStyle(
              decoration:
                  r.completed ? TextDecoration.lineThrough : null,
            )),
        subtitle: Text(
            '${r.patientName}  •  ${d.day}/${d.month}/${d.year}'),
        trailing: r.completed
            ? IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(r),
              )
            : IconButton(
                icon: const Icon(Icons.check_circle_outline),
                color: Colors.green,
                onPressed: () => _markDone(r),
              ),
      ),
    );
  }
}

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
              decoration: const InputDecoration(labelText: 'Mother\'s name')),
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
                : 'LMP: ${_lmp!.day}/${_lmp!.month}/${_lmp!.year} — EDD ${_fmt(MchService.eddFromLmp(_lmp!))}'),
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

  String _fmt(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';
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
                : 'DOB: ${_dob!.day}/${_dob!.month}/${_dob!.year}'),
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

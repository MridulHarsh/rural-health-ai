// inventory_screen.dart
// Medicine-kit inventory for the ASHA worker. List, adjust stock, flag low
// stock and expiring items. Simple CRUD; data is seeded on first launch.

import 'package:flutter/material.dart';

import '../services/inventory_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<MedicineItem> _items = [];
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await InventoryService.getAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _adjust(MedicineItem m, int delta) async {
    if (m.id == null) return;
    await InventoryService.adjustStock(m.id!, delta);
    await _load();
  }

  Future<void> _delete(MedicineItem m) async {
    if (m.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${m.name}" from the kit?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await InventoryService.delete(m.id!);
      await _load();
    }
  }

  Future<void> _addOrEdit({MedicineItem? existing}) async {
    final result = await showModalBottomSheet<MedicineItem>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditSheet(existing: existing),
    );
    if (result == null) return;
    if (existing?.id != null) {
      await InventoryService.update(
        MedicineItem(
          id: existing!.id,
          name: result.name,
          category: result.category,
          stockQty: result.stockQty,
          reorderThreshold: result.reorderThreshold,
          notes: result.notes,
          expiryDate: result.expiryDate,
        ),
      );
    } else {
      await InventoryService.insert(result);
    }
    await _load();
  }

  List<MedicineItem> get _filtered {
    if (_filter.isEmpty) return _items;
    final q = _filter.toLowerCase();
    return _items
        .where((m) =>
            m.name.toLowerCase().contains(q) ||
            m.category.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final lowStockCount = _items.where((m) => m.isLowStock).length;
    final expiringCount = _items.where((m) => m.isExpiringSoon).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ASHA Medicine Kit'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (lowStockCount > 0 || expiringCount > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$lowStockCount low-stock, $expiringCount expiring soon',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search medicines',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No items',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final m = _filtered[i];
                            final stockColor = m.isExpired
                                ? Colors.red.shade700
                                : m.isLowStock
                                    ? Colors.orange.shade700
                                    : Colors.green.shade700;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(m.name),
                                subtitle: Text(
                                  [
                                    m.category,
                                    if (m.isExpired) 'EXPIRED',
                                    if (!m.isExpired && m.isExpiringSoon)
                                      'expires soon',
                                    if (m.isLowStock) 'LOW STOCK',
                                  ].join(' • '),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: (m.isLowStock || m.isExpired)
                                          ? stockColor
                                          : Colors.grey.shade600),
                                ),
                                leading: Container(
                                  width: 56,
                                  height: 56,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: stockColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${m.stockQty}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: stockColor,
                                    ),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle),
                                      color: Colors.red.shade400,
                                      onPressed: () => _adjust(m, -1),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle),
                                      color: Colors.green.shade500,
                                      onPressed: () => _adjust(m, 1),
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (v) {
                                        if (v == 'edit') _addOrEdit(existing: m);
                                        if (v == 'delete') _delete(m);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'edit', child: Text('Edit')),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _EditSheet extends StatefulWidget {
  final MedicineItem? existing;
  const _EditSheet({this.existing});

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _qty;
  late final TextEditingController _reorder;
  DateTime? _expiry;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _category =
        TextEditingController(text: widget.existing?.category ?? 'other');
    _qty = TextEditingController(text: '${widget.existing?.stockQty ?? 0}');
    _reorder =
        TextEditingController(text: '${widget.existing?.reorderThreshold ?? 5}');
    _expiry = widget.existing?.expiryDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _qty.dispose();
    _reorder.dispose();
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
          Text(
            widget.existing == null ? 'Add medicine' : 'Edit medicine',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _name,
              decoration:
                  const InputDecoration(labelText: 'Name (e.g., Paracetamol 500mg)')),
          const SizedBox(height: 8),
          TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Category')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _reorder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Reorder at'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(_expiry == null
                ? 'Set expiry (optional)'
                : 'Expires ${_expiry!.day}/${_expiry!.month}/${_expiry!.year}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _expiry ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              );
              if (picked != null) setState(() => _expiry = picked);
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_name.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                MedicineItem(
                  id: widget.existing?.id,
                  name: _name.text.trim(),
                  category: _category.text.trim().isEmpty
                      ? 'other'
                      : _category.text.trim(),
                  stockQty: int.tryParse(_qty.text) ?? 0,
                  reorderThreshold: int.tryParse(_reorder.text) ?? 5,
                  expiryDate: _expiry,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

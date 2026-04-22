// outbox_screen.dart
// Lists every captured handoff intent — messages the ASHA tried to send to
// the PHC that either couldn't launch (offline) or were launched but she
// wants to re-send. Tapping an item re-opens the composer with the exact
// original payload.
//
// Feature #4 in the NeuCure roadmap.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/translations.dart';
import '../models/handoff_queue_item.dart';
import '../services/connectivity_service.dart';
import '../services/handoff_queue_service.dart';
import '../services/handoff_service.dart';

class OutboxScreen extends StatefulWidget {
  const OutboxScreen({super.key});

  @override
  State<OutboxScreen> createState() => _OutboxScreenState();
}

class _OutboxScreenState extends State<OutboxScreen> {
  List<HandoffQueueItem> _items = const [];
  bool _loading = true;
  bool _online = false;
  String _lang = 'en';

  String _t(String key) => AppTranslations.t(key, _lang);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final items = await HandoffQueueService.list();
    final online = await ConnectivityService.refresh();
    if (!mounted) return;
    setState(() {
      _lang = prefs.getString('language') ?? 'en';
      _items = items;
      _online = online;
      _loading = false;
    });
  }

  Future<void> _retry(HandoffQueueItem item) async {
    final ok = await HandoffService.retryQueueItem(item);
    if (ok) {
      await HandoffQueueService.markLaunched(item.id);
    }
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('outbox_retry_failed'))),
      );
    }
    _load();
  }

  Future<void> _delete(HandoffQueueItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('outbox_delete_title')),
        content: Text(_t('outbox_delete_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await HandoffQueueService.delete(item.id);
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final pending =
        _items.where((i) => i.status == HandoffStatus.pending).toList();
    final launched =
        _items.where((i) => i.status == HandoffStatus.launched).toList();
    return Scaffold(
      appBar: AppBar(title: Text(_t('outbox_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmpty()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildConnectivityBanner(),
                    if (pending.isNotEmpty) ...[
                      _buildSectionHeader(
                        label: _t('outbox_pending_section'),
                        count: pending.length,
                        color: const Color(0xFFD97706),
                      ),
                      const SizedBox(height: 8),
                      for (final it in pending)
                        _OutboxCard(
                          item: it,
                          lang: _lang,
                          online: _online,
                          onRetry: () => _retry(it),
                          onDelete: () => _delete(it),
                        ),
                    ],
                    if (launched.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildSectionHeader(
                        label: _t('outbox_launched_section'),
                        count: launched.length,
                        color: const Color(0xFF16A34A),
                      ),
                      const SizedBox(height: 8),
                      for (final it in launched)
                        _OutboxCard(
                          item: it,
                          lang: _lang,
                          online: _online,
                          onRetry: () => _retry(it),
                          onDelete: () => _delete(it),
                        ),
                    ],
                  ],
                ),
    );
  }

  Widget _buildConnectivityBanner() {
    final online = _online;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: online
            ? const Color(0xFFDCFCE7)
            : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            color: online
                ? const Color(0xFF16A34A)
                : const Color(0xFFD97706),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              online ? _t('outbox_online') : _t('outbox_offline'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: online
                    ? const Color(0xFF166534)
                    : const Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String label,
    required int count,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '($count)',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.outbox_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _t('outbox_empty'),
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _t('outbox_empty_body'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutboxCard extends StatelessWidget {
  final HandoffQueueItem item;
  final String lang;
  final bool online;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const _OutboxCard({
    required this.item,
    required this.lang,
    required this.online,
    required this.onRetry,
    required this.onDelete,
  });

  String _t(String key) => AppTranslations.t(key, lang);

  @override
  Widget build(BuildContext context) {
    final pending = item.status == HandoffStatus.pending;
    final retryDisabled = pending && !online;

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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kindColor(item.kind).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_kindIcon(item.kind),
                      size: 18, color: _kindColor(item.kind)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _kindLabel(item.kind),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(item.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                _statusChip(pending),
              ],
            ),
            if (item.label != null && item.label!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                item.label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
            if (item.payload.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.payload,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            if (item.recipient != null && item.recipient!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${_t('outbox_recipient')}: ${item.recipient}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: retryDisabled ? null : onRetry,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      pending
                          ? _t('outbox_send_now')
                          : _t('outbox_resend'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.grey.shade500,
                  tooltip: _t('delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(bool pending) {
    final color = pending
        ? const Color(0xFFD97706)
        : const Color(0xFF16A34A);
    final label = pending ? _t('outbox_pending') : _t('outbox_launched');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  IconData _kindIcon(HandoffKind kind) {
    switch (kind) {
      case HandoffKind.whatsapp:
        return Icons.chat_rounded;
      case HandoffKind.sms:
        return Icons.sms_rounded;
      case HandoffKind.fhirShare:
        return Icons.description_rounded;
    }
  }

  Color _kindColor(HandoffKind kind) {
    switch (kind) {
      case HandoffKind.whatsapp:
        return const Color(0xFF25D366);
      case HandoffKind.sms:
        return const Color(0xFF6366F1);
      case HandoffKind.fhirShare:
        return const Color(0xFF0EA5E9);
    }
  }

  String _kindLabel(HandoffKind kind) {
    switch (kind) {
      case HandoffKind.whatsapp:
        return _t('outbox_kind_whatsapp');
      case HandoffKind.sms:
        return _t('outbox_kind_sms');
      case HandoffKind.fhirShare:
        return _t('outbox_kind_fhir');
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return _t('outbox_just_now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

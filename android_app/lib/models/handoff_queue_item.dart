// handoff_queue_item.dart
// An entry in the Outbox — a captured intent to send an assessment summary
// to a downstream recipient (PHC physician, district coordinator, etc.).
//
// Queue semantics (honest version):
//   pending   — created, not yet launched. Usually because the device was
//               offline when the ASHA tapped send. This is what the home
//               badge counts.
//   launched  — the WhatsApp/SMS composer was successfully opened, OR the
//               share sheet returned. We can NOT confirm delivery from our
//               side (we don't see WhatsApp's own queue), so this status is
//               a best-effort "the ASHA was given the opportunity to send."
//
// The payload is encrypted at rest (AES-GCM via EncryptionService) — it
// contains the patient name + conditions + notes. The recipient phone is
// also PII under DPDP and is encrypted the same way.

import 'dart:convert';

/// What kind of handoff this item represents.
enum HandoffKind {
  whatsapp,
  sms,
  fhirShare,
}

/// Queue item status. See file header for semantics.
enum HandoffStatus {
  pending,
  launched,
}

/// A single row in the `handoff_queue` table.
class HandoffQueueItem {
  final String id;
  final HandoffKind kind;

  /// Plaintext message body. For `fhirShare` this is a short cover note; the
  /// actual bundle JSON lives on disk at [filePath].
  final String payload;

  /// Optional phone number (whatsapp / sms only). Plaintext in-memory;
  /// encrypted at rest.
  final String? recipient;

  /// Optional absolute path to a backing file (fhirShare only). We pin FHIR
  /// bundles to app documents (not cache) so they survive reclamation until
  /// the user either re-shares or deletes the queue item.
  final String? filePath;

  /// Optional SHA-256 prefix for dedup / audit display (fhirShare only).
  final String? fileHash;

  final HandoffStatus status;
  final int attempts;
  final DateTime createdAt;
  final DateTime? lastTriedAt;

  /// Short display label (e.g. "Referral for Anita — sepsis"). Encrypted at
  /// rest because it typically includes the patient first name.
  final String? label;

  HandoffQueueItem({
    required this.id,
    required this.kind,
    required this.payload,
    this.recipient,
    this.filePath,
    this.fileHash,
    this.status = HandoffStatus.pending,
    this.attempts = 0,
    DateTime? createdAt,
    this.lastTriedAt,
    this.label,
  }) : createdAt = createdAt ?? DateTime.now();

  HandoffQueueItem copyWith({
    HandoffStatus? status,
    int? attempts,
    DateTime? lastTriedAt,
  }) =>
      HandoffQueueItem(
        id: id,
        kind: kind,
        payload: payload,
        recipient: recipient,
        filePath: filePath,
        fileHash: fileHash,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        createdAt: createdAt,
        lastTriedAt: lastTriedAt ?? this.lastTriedAt,
        label: label,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'payload': payload,
        'recipient': recipient,
        'filePath': filePath,
        'fileHash': fileHash,
        'status': status.name,
        'attempts': attempts,
        'createdAt': createdAt.toIso8601String(),
        'lastTriedAt': lastTriedAt?.toIso8601String(),
        'label': label,
      };

  String toJsonString() => jsonEncode(toJson());

  static HandoffKind kindFromName(String? name) =>
      HandoffKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => HandoffKind.whatsapp,
      );

  static HandoffStatus statusFromName(String? name) =>
      HandoffStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => HandoffStatus.pending,
      );
}

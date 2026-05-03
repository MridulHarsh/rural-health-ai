// fhir_service.dart
// Builds a FHIR R4 Bundle (type: document) from an AssessmentResult so the
// encounter can be shared with an ABDM-compliant HIU (Health Information User).
//
// Feature #1 in the NeuCure roadmap: ABHA-linked encounter export. We do NOT
// push to a live ABDM gateway — that's a Phase 2 integration once consent
// artefact flow is built. For MVP the bundle is rendered as JSON and attached
// via the existing WhatsApp / SMS / file-share handoff, which is enough for
// the ABHA-holder and a downstream physician to reconcile the record.
//
// The bundle is deterministic: given the same AssessmentResult, the same JSON
// (and the same SHA-256 provenance hash) comes out every time. That makes it
// safe to re-send on retry without the receiver seeing "two different records"
// for one encounter — the hash is the dedup key.
//
// References:
//   FHIR R4 Bundle spec   — https://hl7.org/fhir/R4/bundle.html
//   ABHA identifier URIs  — NDHM / ABDM sandbox docs (abdm.gov.in)
//   LOINC vital codes     — https://loinc.org (standard panel codes used below)
//
// We deliberately do not depend on a third-party FHIR SDK — those libraries
// pull in ~MBs of transitive code for what is, at this level, just a typed
// JSON builder. Keeping the APK lean matters on rural 2 GB phones.
//
// Clinical-data codings:
//   Vitals → LOINC (universal)
//   Conditions → local CodeSystem (urn:rha:disease-profile); the 162 curated
//     DiseaseProfile IDs don't have a 1:1 SNOMED/ICD-10 mapping today and
//     fake-coding them would mislead a receiving system. The canonical ID +
//     human-readable display is honest and reversible.

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../models/patient.dart';

class FhirBundleService {
  // URL namespace gives us stable, collision-resistant v5 UUIDs. Any string
  // derived from the assessment (patient ID + role) gets the same UUID every
  // time — the entire bundle is reproducible from the source AssessmentResult.
  static const _uuid = Uuid();

  /// System URIs for the ABHA identifiers on Patient. Matches the values
  /// published in the ABDM sandbox so an HIU can route on `identifier.system`.
  static const _abhaIdSystem = 'https://healthid.ndhm.gov.in';
  static const _abhaAddressSystem = 'https://abdm.gov.in/ABHA-address';

  /// Local CodeSystem for DiseaseProfile canonical IDs. Scoped to this app —
  /// receivers should treat it as informational and not try to SNOMED-map it.
  static const _diseaseCodeSystem = 'urn:rha:disease-profile';

  /// Build a FHIR R4 Bundle as a JSON-serializable map. Pair with
  /// [toJsonString] for the wire format, or call [computeHash] directly on
  /// the map for the provenance digest.
  static Map<String, dynamic> buildBundle(AssessmentResult result) {
    final patientUuid = _stableUuid('patient:${result.patient.id}');
    final compositionUuid = _stableUuid('composition:${result.patient.id}');
    final timestamp = result.assessedAt.toUtc().toIso8601String();

    final observations = _buildObservations(result, patientUuid, timestamp);
    final conditions = _buildConditions(result, patientUuid, timestamp);
    final impressionUuid = _stableUuid('impression:${result.patient.id}');

    final composition = _buildComposition(
      compositionUuid: compositionUuid,
      patientUuid: patientUuid,
      result: result,
      observations: observations,
      conditions: conditions,
      impressionUuid: impressionUuid,
      timestamp: timestamp,
    );

    final clinicalImpression = _buildClinicalImpression(
      impressionUuid: impressionUuid,
      patientUuid: patientUuid,
      result: result,
      conditionEntries: conditions,
      timestamp: timestamp,
    );

    // Order matters for type=document: Composition MUST be first. The rest
    // can be in any order; we use Patient → Observations → Conditions →
    // ClinicalImpression for readability when a receiver pretty-prints.
    final entries = <Map<String, dynamic>>[
      _entry(compositionUuid, composition),
      _entry(patientUuid, _buildPatient(patientUuid, result.patient)),
      for (final o in observations) _entry(o.uuid, o.resource),
      for (final c in conditions) _entry(c.uuid, c.resource),
      _entry(impressionUuid, clinicalImpression),
    ];

    return {
      'resourceType': 'Bundle',
      'id': _stableUuid('bundle:${result.patient.id}'),
      'meta': {
        'profile': ['http://hl7.org/fhir/StructureDefinition/Bundle'],
      },
      'type': 'document',
      'timestamp': timestamp,
      'entry': entries,
    };
  }

  /// JSON string representation of the bundle. Pretty-printed for readability
  /// (rural PHC physicians may read it directly in WhatsApp).
  static String toJsonString(Map<String, dynamic> bundle) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(bundle);
  }

  /// SHA-256 hex digest of the bundle's canonical (sorted-keys, no-whitespace)
  /// JSON form. Use this as the dedup / provenance key when the same bundle
  /// is re-sent to multiple HIUs or retried after a flaky network.
  static String computeHash(Map<String, dynamic> bundle) {
    final canonical = _canonicalJson(bundle);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  // ───────────────────────── resource builders ─────────────────────────

  static Map<String, dynamic> _buildPatient(String uuid, Patient p) {
    final birthDate = _birthDateFromAge(p.age, p.createdAt);
    final identifiers = <Map<String, dynamic>>[];

    final abhaId = p.abhaId?.trim();
    if (abhaId != null && abhaId.isNotEmpty) {
      identifiers.add({
        'system': _abhaIdSystem,
        'value': abhaId,
        'use': 'official',
      });
    }
    final abhaAddress = p.abhaAddress?.trim();
    if (abhaAddress != null && abhaAddress.isNotEmpty) {
      identifiers.add({
        'system': _abhaAddressSystem,
        'value': abhaAddress,
        'use': 'official',
      });
    }

    return {
      'resourceType': 'Patient',
      'id': uuid,
      if (identifiers.isNotEmpty) 'identifier': identifiers,
      'name': [
        {
          'use': 'official',
          'text': p.name,
        },
      ],
      'gender': _fhirGender(p.gender),
      'birthDate': birthDate,
    };
  }

  static List<_Entry> _buildObservations(
    AssessmentResult result,
    String patientUuid,
    String timestamp,
  ) {
    final v = result.vitals;
    final patientRef = 'urn:uuid:$patientUuid';
    final out = <_Entry>[];

    if (v.temperature != null) {
      out.add(_vitalObservation(
        key: 'temp',
        patientId: result.patient.id,
        patientRef: patientRef,
        timestamp: timestamp,
        loincCode: '8310-5',
        display: 'Body temperature',
        value: v.temperature!,
        unit: '°F',
        unitCode: '[degF]',
      ));
    }
    if (v.heartRate != null) {
      out.add(_vitalObservation(
        key: 'hr',
        patientId: result.patient.id,
        patientRef: patientRef,
        timestamp: timestamp,
        loincCode: '8867-4',
        display: 'Heart rate',
        value: v.heartRate!.toDouble(),
        unit: 'beats/min',
        unitCode: '/min',
      ));
    }
    if (v.spo2 != null) {
      out.add(_vitalObservation(
        key: 'spo2',
        patientId: result.patient.id,
        patientRef: patientRef,
        timestamp: timestamp,
        loincCode: '59408-5',
        display: 'Oxygen saturation in arterial blood by pulse oximetry',
        value: v.spo2!.toDouble(),
        unit: '%',
        unitCode: '%',
      ));
    }
    if (v.weight != null) {
      out.add(_vitalObservation(
        key: 'weight',
        patientId: result.patient.id,
        patientRef: patientRef,
        timestamp: timestamp,
        loincCode: '29463-7',
        display: 'Body weight',
        value: v.weight!,
        unit: 'kg',
        unitCode: 'kg',
      ));
    }
    if (v.height != null) {
      out.add(_vitalObservation(
        key: 'height',
        patientId: result.patient.id,
        patientRef: patientRef,
        timestamp: timestamp,
        loincCode: '8302-2',
        display: 'Body height',
        value: v.height!,
        unit: 'cm',
        unitCode: 'cm',
      ));
    }
    // Blood pressure is a LOINC panel (85354-9) with systolic + diastolic as
    // components. Splitting it into two independent Observations is wrong —
    // receivers that expect the panel won't correlate them.
    final bp = v.bloodPressure;
    if (bp != null && bp.contains('/')) {
      final parts = bp.split('/');
      final sys = double.tryParse(parts[0].trim());
      final dia = double.tryParse(parts[1].trim());
      if (sys != null && dia != null) {
        final uuid = _stableUuid('obs:bp:${result.patient.id}');
        out.add(_Entry(
          uuid: uuid,
          resource: {
            'resourceType': 'Observation',
            'id': uuid,
            'status': 'final',
            'category': [_vitalSignsCategory()],
            'code': _loincCodeable('85354-9', 'Blood pressure panel'),
            'subject': {'reference': patientRef},
            'effectiveDateTime': timestamp,
            'component': [
              {
                'code': _loincCodeable('8480-6', 'Systolic blood pressure'),
                'valueQuantity': _quantity(sys, 'mmHg', 'mm[Hg]'),
              },
              {
                'code': _loincCodeable('8462-4', 'Diastolic blood pressure'),
                'valueQuantity': _quantity(dia, 'mmHg', 'mm[Hg]'),
              },
            ],
          },
        ));
      }
    }

    return out;
  }

  static _Entry _vitalObservation({
    required String key,
    required String patientId,
    required String patientRef,
    required String timestamp,
    required String loincCode,
    required String display,
    required double value,
    required String unit,
    required String unitCode,
  }) {
    final uuid = _stableUuid('obs:$key:$patientId');
    return _Entry(
      uuid: uuid,
      resource: {
        'resourceType': 'Observation',
        'id': uuid,
        'status': 'final',
        'category': [_vitalSignsCategory()],
        'code': _loincCodeable(loincCode, display),
        'subject': {'reference': patientRef},
        'effectiveDateTime': timestamp,
        'valueQuantity': _quantity(value, unit, unitCode),
      },
    );
  }

  static List<_Entry> _buildConditions(
    AssessmentResult result,
    String patientUuid,
    String timestamp,
  ) {
    final patientRef = 'urn:uuid:$patientUuid';
    final out = <_Entry>[];
    for (var i = 0; i < result.conditions.length; i++) {
      final c = result.conditions[i];
      final uuid = _stableUuid('cond:${c.canonicalId}:${result.patient.id}');
      final notes = <Map<String, dynamic>>[];
      if (c.reasoning != null && c.reasoning!.isNotEmpty) {
        notes.add({'text': c.reasoning!});
      }
      out.add(_Entry(
        uuid: uuid,
        resource: {
          'resourceType': 'Condition',
          'id': uuid,
          'clinicalStatus': {
            'coding': [
              {
                'system':
                    'http://terminology.hl7.org/CodeSystem/condition-clinical',
                'code': 'active',
              },
            ],
          },
          // "provisional" signals to the receiving physician that this is an
          // algorithmic suggestion, not a confirmed clinician diagnosis —
          // critical distinction for medico-legal review of the record.
          'verificationStatus': {
            'coding': [
              {
                'system':
                    'http://terminology.hl7.org/CodeSystem/condition-ver-status',
                'code': 'provisional',
              },
            ],
          },
          'category': [
            {
              'coding': [
                {
                  'system':
                      'http://terminology.hl7.org/CodeSystem/condition-category',
                  'code': 'encounter-diagnosis',
                  'display': 'Encounter Diagnosis',
                },
              ],
            },
          ],
          'code': {
            'coding': [
              {
                'system': _diseaseCodeSystem,
                'code': c.canonicalId,
                'display': c.name,
              },
            ],
            'text': c.name,
          },
          'subject': {'reference': patientRef},
          'recordedDate': timestamp,
          // Confidence is out-of-band in FHIR R4; the best fit is an extension
          // but that requires URL ownership. Surface it as a note instead so
          // no information is lost on the wire.
          'note': [
            {
              'text':
                  'AI confidence ${(c.confidence * 100).toStringAsFixed(0)}%, '
                      'risk ${c.riskLevel.name}',
            },
            ...notes,
          ],
        },
      ));
    }
    return out;
  }

  static Map<String, dynamic> _buildComposition({
    required String compositionUuid,
    required String patientUuid,
    required AssessmentResult result,
    required List<_Entry> observations,
    required List<_Entry> conditions,
    required String impressionUuid,
    required String timestamp,
  }) {
    final sections = <Map<String, dynamic>>[];
    if (observations.isNotEmpty) {
      sections.add({
        'title': 'Vital Signs',
        'code': _loincCodeable('8716-3', 'Vital signs'),
        'entry': [
          for (final o in observations) {'reference': 'urn:uuid:${o.uuid}'},
        ],
      });
    }
    if (conditions.isNotEmpty) {
      sections.add({
        'title': 'Assessment',
        'code':
            _loincCodeable('51848-0', 'Evaluation note'),
        'entry': [
          for (final c in conditions) {'reference': 'urn:uuid:${c.uuid}'},
        ],
      });
    }
    sections.add({
      'title': 'Clinical Impression',
      'code': _loincCodeable('51847-2', 'Evaluation + Plan note'),
      'entry': [
        {'reference': 'urn:uuid:$impressionUuid'},
      ],
    });

    return {
      'resourceType': 'Composition',
      'id': compositionUuid,
      'status': 'final',
      'type': _loincCodeable('11488-4', 'Consultation note'),
      'subject': {'reference': 'urn:uuid:$patientUuid'},
      'date': timestamp,
      'author': [
        {
          'display': 'Rural Health AI Assistant (ASHA handheld)',
        },
      ],
      'title': 'Clinical Assessment Summary',
      'section': sections,
    };
  }

  static Map<String, dynamic> _buildClinicalImpression({
    required String impressionUuid,
    required String patientUuid,
    required AssessmentResult result,
    required List<_Entry> conditionEntries,
    required String timestamp,
  }) {
    final summaryParts = <String>[
      'Overall risk: ${result.overallRisk.name}.',
    ];
    final redFlag = result.redFlag;
    if (redFlag != null) {
      summaryParts.add(
        'RED FLAG: ${redFlag.conditionName} — ${redFlag.immediateAction}.',
      );
    }
    if (result.implicatedSystems.isNotEmpty) {
      summaryParts
          .add('Implicated systems: ${result.implicatedSystems.join(', ')}.');
    }
    if (result.nextSteps.isNotEmpty) {
      summaryParts.add('Next steps: ${result.nextSteps.join('; ')}.');
    }

    return {
      'resourceType': 'ClinicalImpression',
      'id': impressionUuid,
      'status': 'completed',
      'subject': {'reference': 'urn:uuid:$patientUuid'},
      'date': timestamp,
      'summary': summaryParts.join(' '),
      'finding': [
        for (final c in conditionEntries)
          {
            'itemReference': {'reference': 'urn:uuid:${c.uuid}'},
          },
      ],
    };
  }

  // ───────────────────────── helpers ─────────────────────────

  static Map<String, dynamic> _entry(String uuid, Map<String, dynamic> body) =>
      {
        'fullUrl': 'urn:uuid:$uuid',
        'resource': body,
      };

  static Map<String, dynamic> _vitalSignsCategory() => {
        'coding': [
          {
            'system':
                'http://terminology.hl7.org/CodeSystem/observation-category',
            'code': 'vital-signs',
            'display': 'Vital Signs',
          },
        ],
      };

  static Map<String, dynamic> _loincCodeable(String code, String display) => {
        'coding': [
          {
            'system': 'http://loinc.org',
            'code': code,
            'display': display,
          },
        ],
        'text': display,
      };

  static Map<String, dynamic> _quantity(
    double value,
    String unit,
    String unitCode,
  ) =>
      {
        'value': value,
        'unit': unit,
        'system': 'http://unitsofmeasure.org',
        'code': unitCode,
      };

  /// Approximate birthDate from age. FHIR expects `YYYY` | `YYYY-MM` |
  /// `YYYY-MM-DD`; we use `YYYY` because ages in this flow are whole-year
  /// estimates from the ASHA worker — a synthetic month/day would be fake
  /// precision.
  static String _birthDateFromAge(int age, DateTime assessedAt) {
    final year = assessedAt.toUtc().year - age;
    return year.toString().padLeft(4, '0');
  }

  /// FHIR `administrative-gender` is a closed value set (male | female | other
  /// | unknown). The app collects free-text gender; normalize without dropping
  /// non-binary patients.
  static String _fhirGender(String raw) {
    final g = raw.trim().toLowerCase();
    if (g == 'm' || g == 'male') return 'male';
    if (g == 'f' || g == 'female') return 'female';
    if (g.isEmpty) return 'unknown';
    return 'other';
  }

  static String _stableUuid(String seed) =>
      _uuid.v5(Namespace.url.value, seed);

  /// Canonicalize a JSON value for hashing: sort all object keys recursively
  /// and drop whitespace. RFC 8785 (JCS) is overkill for our needs — our
  /// values are plain JSON scalars (no floating-point edge cases). The
  /// receiver re-hashes using the same rule to verify provenance.
  static String _canonicalJson(Object? value) {
    final buffer = StringBuffer();
    _writeCanonical(buffer, value);
    return buffer.toString();
  }

  static void _writeCanonical(StringBuffer buf, Object? value) {
    if (value == null) {
      buf.write('null');
    } else if (value is String) {
      buf.write(jsonEncode(value));
    } else if (value is num || value is bool) {
      buf.write(jsonEncode(value));
    } else if (value is List) {
      buf.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) buf.write(',');
        _writeCanonical(buf, value[i]);
      }
      buf.write(']');
    } else if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      buf.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(jsonEncode(keys[i]));
        buf.write(':');
        _writeCanonical(buf, value[keys[i]]);
      }
      buf.write('}');
    } else {
      buf.write(jsonEncode(value.toString()));
    }
  }
}

class _Entry {
  final String uuid;
  final Map<String, dynamic> resource;
  _Entry({required this.uuid, required this.resource});
}

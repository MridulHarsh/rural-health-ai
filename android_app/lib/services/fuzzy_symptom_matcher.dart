import 'clinical_knowledge.dart';

/// Fuzzy symptom matcher for voice input.
/// Uses edit distance + substring matching to handle
/// imprecise speech recognition across all languages.
class FuzzySymptomMatcher {
  static final FuzzySymptomMatcher _instance = FuzzySymptomMatcher._();
  factory FuzzySymptomMatcher() => _instance;
  FuzzySymptomMatcher._();

  // Pre-built lookup: all known terms → canonical symptom key
  // Includes symptomAliases + all keys from symptomSystemMap
  Map<String, String>? _lookup;

  Map<String, String> get _allTerms {
    if (_lookup != null) return _lookup!;
    _lookup = <String, String>{};

    // Add all aliases, resolving alias chains so every term maps directly to
    // its final canonical. Without this, e.g. "सांस फूलना" → "breathlessness"
    // stops mid-chain because "breathlessness" is itself only an alias to
    // "shortness_of_breath". Flattening at load time gives O(1) lookup later.
    for (final e in symptomAliases.entries) {
      final canonical = _resolveChain(e.key);
      _lookup![e.key.toLowerCase()] = canonical;
      _lookup![e.key] = canonical; // Keep original case for native script
    }

    // Add all canonical symptom keys (they match themselves)
    for (final key in symptomSystemMap.keys) {
      _lookup![key] = key;
      // Also add human-readable version: "chest_pain" -> "chest pain"
      _lookup![key.replaceAll('_', ' ')] = key;
    }

    return _lookup!;
  }

  /// Follow an alias chain until it reaches a terminal string. Cycle-safe.
  static String _resolveChain(String key) {
    String current = key;
    final seen = <String>{};
    while (symptomAliases.containsKey(current) && !seen.contains(current)) {
      seen.add(current);
      final next = symptomAliases[current]!;
      if (next == current) break;
      current = next;
    }
    return current;
  }

  /// Extract symptoms from a voice transcript using fuzzy matching.
  /// Returns a set of canonical symptom keys.
  Set<String> extractSymptoms(String transcript) {
    final found = <String>{};
    if (transcript.trim().isEmpty) return found;

    final terms = _allTerms;
    final text = transcript;
    final textLower = transcript.toLowerCase();

    // 1. Exact substring matching (fast path for native script)
    //    Only check aliases that are 3+ chars to avoid false positives
    for (final e in terms.entries) {
      if (e.key.length >= 3) {
        if (text.contains(e.key) || textLower.contains(e.key.toLowerCase())) {
          found.add(e.value);
        }
      }
    }

    // 2. Word-level fuzzy matching
    final words = _splitWords(text);

    for (final word in words) {
      if (word.length < 2) continue;
      final wLower = word.toLowerCase();

      // Exact match first
      if (terms.containsKey(word)) {
        found.add(terms[word]!);
        continue;
      }
      if (terms.containsKey(wLower)) {
        found.add(terms[wLower]!);
        continue;
      }

      // Fuzzy match: find closest term within edit distance threshold
      final match = _fuzzyMatch(wLower, terms);
      if (match != null) found.add(match);
    }

    // 3. Two-word phrase matching
    for (int i = 0; i < words.length - 1; i++) {
      final phrase = '${words[i]} ${words[i + 1]}';
      final phraseLower = phrase.toLowerCase();
      final underscored = '${words[i].toLowerCase()}_${words[i + 1].toLowerCase()}';

      if (terms.containsKey(phrase)) {
        found.add(terms[phrase]!);
      } else if (terms.containsKey(phraseLower)) {
        found.add(terms[phraseLower]!);
      } else if (terms.containsKey(underscored)) {
        found.add(terms[underscored]!);
      } else {
        // Fuzzy match on phrase
        final match = _fuzzyMatch(phraseLower, terms);
        if (match != null) found.add(match);
      }
    }

    // 4. Three-word phrase matching
    for (int i = 0; i < words.length - 2; i++) {
      final phrase = '${words[i]} ${words[i + 1]} ${words[i + 2]}'.toLowerCase();
      if (terms.containsKey(phrase)) {
        found.add(terms[phrase]!);
      }
    }

    return found;
  }

  /// Split text into words, preserving Unicode (Indic scripts)
  List<String> _splitWords(String text) {
    return text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Find the best fuzzy match for a word in the terms map.
  /// Returns the canonical symptom key, or null if no good match.
  String? _fuzzyMatch(String word, Map<String, String> terms) {
    if (word.length < 3) return null; // Too short for fuzzy matching

    // Threshold: allow ~30% character errors
    final maxDist = (word.length * 0.3).ceil().clamp(1, 3);

    String? bestMatch;
    int bestDist = maxDist + 1;

    for (final e in terms.entries) {
      final term = e.key.toLowerCase();

      // Skip if length difference is too large
      if ((term.length - word.length).abs() > maxDist) continue;

      // Skip very short terms for fuzzy (high false positive rate)
      if (term.length < 3) continue;

      final dist = _editDistance(word, term);
      if (dist < bestDist) {
        bestDist = dist;
        bestMatch = e.value;
        if (dist == 0) break; // Perfect match
      }
    }

    return bestDist <= maxDist ? bestMatch : null;
  }

  /// Levenshtein edit distance between two strings.
  /// Optimized with early termination.
  int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Ensure a is the shorter string for space efficiency
    if (a.length > b.length) {
      final tmp = a; a = b; b = tmp;
    }

    final m = a.length;
    final n = b.length;

    // Single row DP
    var prev = List<int>.generate(m + 1, (i) => i);
    var curr = List<int>.filled(m + 1, 0);

    for (int j = 1; j <= n; j++) {
      curr[0] = j;
      for (int i = 1; i <= m; i++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[i] = [
          prev[i] + 1,     // deletion
          curr[i - 1] + 1, // insertion
          prev[i - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
      final tmp = prev; prev = curr; curr = tmp;
    }

    return prev[m];
  }
}

import '../models/playable_channel.dart';
import '../models/xmltv_guide.dart';

/// 30.09, Sid: "un vrai lecteur iptv sera mieux que celui de moon basé sur
/// emby" - matches a playlist's channels against a separate XMLTV guide's
/// channel list, since the two almost never use the same IDs or exact
/// names. Multi-strategy scoring algorithm adapted from clubTivi's
/// EpgAutoMapper (github.com/clubanderson/clubTivi,
/// lib/data/services/epg_auto_mapper.dart, Apache License 2.0) - rewritten
/// against Moonfin's own PlayableChannel/XmltvChannel types rather than a
/// straight port, channel-number and logo-URL strategies dropped (an M3U
/// playlist entry has neither), Jaro-Winkler implemented locally since
/// nothing in Moonfin already provided one.
class EpgMatch {
  final XmltvChannel channel;
  final double confidence;
  final String strategy;

  const EpgMatch({
    required this.channel,
    required this.confidence,
    required this.strategy,
  });
}

class EpgChannelMatcher {
  static const _autoApplyThreshold = 0.70;

  static final _qualityTagPattern = RegExp(
    r'\b(hd|fhd|shd|sd|4k|uhd)\b',
    caseSensitive: false,
  );
  static final _separatorPattern = RegExp(r'[\s|()\[\].,_-]+');
  static final _callSignPattern = RegExp(r'\(([a-z0-9]+)\)', caseSensitive: false);
  static final _leadingRegionPattern = RegExp(r'^[a-z]{2,3}\s*[:|/-]\s*', caseSensitive: false);

  /// 03.10, Sid: "nettoyer l'affichage en supprimant ces infos" (préfixes
  /// pays/région style "FR|", "DE:", "CH-" devant le nom réel d'une
  /// chaîne) - un simple wrapper d'affichage autour du même motif déjà
  /// éprouvé pour le matching EPG (_leadingRegionPattern/segments
  /// pipe-séparés), mais qui garde la casse et la ponctuation du nom
  /// réel au lieu de le normaliser en minuscules comme _cleanChannelName
  /// le fait pour comparer. N'affecte jamais channel.name lui-même (pas
  /// de risque pour le matching EPG ou la clé de regroupement des
  /// favoris, qui utilisent toujours le nom brut).
  static String displayName(String name) {
    var result = name;
    final segments = result.split('|');
    if (segments.length > 1) {
      result = segments.last;
    }
    result = result.replaceAll(_leadingRegionPattern, '');
    result = result.trim();
    return result.isEmpty ? name.trim() : result;
  }

  /// Builds a lookup index once per guide so matching every playlist
  /// channel against it doesn't re-scan the whole channel list each time.
  static _GuideIndex _buildIndex(XmltvGuide guide) {
    final byId = <String, XmltvChannel>{};
    final byNormalizedName = <String, XmltvChannel>{};
    for (final ch in guide.channels) {
      byId[ch.id] = ch;
      byId[_normalize(ch.id)] = ch;
      for (final name in ch.displayNames) {
        final normalized = _normalize(name);
        if (normalized.isNotEmpty) {
          byNormalizedName.putIfAbsent(normalized, () => ch);
        }
        final callSign = _extractCallSign(name);
        if (callSign != null) {
          byNormalizedName.putIfAbsent(callSign, () => ch);
        }
      }
    }
    return _GuideIndex(byId: byId, byNormalizedName: byNormalizedName);
  }

  /// Best match for one playlist channel against [guide], or null under
  /// [_autoApplyThreshold] - a low-confidence guess is worse than no EPG at
  /// all, it would show the wrong programme with full confidence.
  static EpgMatch? match(PlayableChannel channel, XmltvGuide guide) {
    final index = _buildIndex(guide);
    EpgMatch? best;

    void consider(XmltvChannel? ch, double score, String strategy) {
      if (ch == null) return;
      if (best == null || score > best!.confidence) {
        best = EpgMatch(channel: ch, confidence: score, strategy: strategy);
      }
    }

    // Strategy 1: exact tvg-id against the guide's own channel id.
    final tvgId = channel.tvgId;
    if (tvgId != null && tvgId.isNotEmpty) {
      consider(index.byId[tvgId], 1.0, 'exact_tvg_id');
      consider(index.byId[_normalize(tvgId)], 0.95, 'normalized_id');
      final callSign = _extractCallSign(tvgId) ?? _normalize(tvgId);
      consider(index.byNormalizedName[callSign], 0.9, 'tvg_id_call_sign');
    }

    // Strategy 2: fuzzy match on the channel's own display name.
    final cleanedName = _cleanChannelName(channel.name);
    if (cleanedName.isNotEmpty) {
      final exact = index.byNormalizedName[cleanedName];
      if (exact != null) {
        consider(exact, 0.95, 'exact_name');
      } else {
        for (final entry in index.byNormalizedName.entries) {
          final score = _fuzzyScore(cleanedName, entry.key);
          if (score >= 0.55) {
            consider(entry.value, score.clamp(0.0, 0.95), 'fuzzy_name');
          }
        }
      }
    }

    final result = best;
    if (result == null || result.confidence < _autoApplyThreshold) {
      return null;
    }
    return result;
  }

  static List<XmltvProgramme> programmesFor(
    XmltvChannel channel,
    XmltvGuide guide,
  ) {
    return guide.programmes.where((p) => p.channelId == channel.id).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  /// A stable cross-provider grouping key for a channel's own display name
  /// (call-sign when present, normalized name otherwise) - used by
  /// ChannelGroup to find "the same channel" across different Xtream/M3U
  /// providers, independent of whether either one has an XMLTV match.
  static String groupingKey(String name) {
    final cleaned = _cleanChannelName(name);
    return _extractCallSign(name) ?? cleaned;
  }

  static String _normalize(String name) {
    var result = name.toLowerCase();
    result = result.replaceAll(_qualityTagPattern, '');
    result = result.replaceAll(_separatorPattern, ' ');
    return result.trim();
  }

  /// Pulls a call-sign out of a parenthesised segment, e.g.
  /// "ABC 7 (WABC)" -> "wabc" - IPTV playlists and guides disagree on
  /// display names constantly but tend to agree on the call-sign when both
  /// include one.
  static String? _extractCallSign(String name) {
    final match = _callSignPattern.firstMatch(name);
    if (match == null) return null;
    final sign = match.group(1);
    return sign != null && sign.isNotEmpty ? sign.toLowerCase() : null;
  }

  static String _cleanChannelName(String name) {
    var result = name;
    // "NY | New York | ABC 7" -> "ABC 7": take the last segment, playlists
    // commonly prefix region info this way.
    final segments = result.split('|');
    if (segments.length > 1) {
      result = segments.last;
    }
    result = result.replaceAll(_leadingRegionPattern, '');
    return _normalize(result);
  }

  /// 1.0 for identical strings, 0.8 for one containing the other, otherwise
  /// the higher of a token-overlap (Jaccard) score and Jaro-Winkler
  /// similarity.
  static double _fuzzyScore(String a, String b) {
    if (a == b) return 0.95;
    if (a.contains(b) || b.contains(a)) return 0.8;
    final jaccard = _jaccardTokenScore(a, b);
    final jaroWinkler = _jaroWinkler(a, b);
    return jaccard > jaroWinkler ? jaccard : jaroWinkler;
  }

  static double _jaccardTokenScore(String a, String b) {
    final tokensA = a.split(' ').where((t) => t.isNotEmpty).toSet();
    final tokensB = b.split(' ').where((t) => t.isNotEmpty).toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) return 0.0;
    final intersection = tokensA.intersection(tokensB).length;
    final union = tokensA.union(tokensB).length;
    return union == 0 ? 0.0 : intersection / union;
  }

  static double _jaroWinkler(String a, String b) {
    final jaro = _jaro(a, b);
    if (jaro < 0.7) return jaro;
    var prefixLength = 0;
    final maxPrefix = a.length < b.length ? a.length : b.length;
    while (prefixLength < maxPrefix &&
        prefixLength < 4 &&
        a[prefixLength] == b[prefixLength]) {
      prefixLength++;
    }
    return jaro + prefixLength * 0.1 * (1 - jaro);
  }

  static double _jaro(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;

    final matchDistance = (a.length > b.length ? a.length : b.length) ~/ 2 - 1;
    final aMatches = List<bool>.filled(a.length, false);
    final bMatches = List<bool>.filled(b.length, false);

    var matches = 0;
    for (var i = 0; i < a.length; i++) {
      final start = (i - matchDistance).clamp(0, b.length);
      final end = (i + matchDistance + 1).clamp(0, b.length);
      for (var j = start; j < end; j++) {
        if (bMatches[j] || a[i] != b[j]) continue;
        aMatches[i] = true;
        bMatches[j] = true;
        matches++;
        break;
      }
    }
    if (matches == 0) return 0.0;

    var transpositions = 0;
    var k = 0;
    for (var i = 0; i < a.length; i++) {
      if (!aMatches[i]) continue;
      while (!bMatches[k]) {
        k++;
      }
      if (a[i] != b[k]) transpositions++;
      k++;
    }

    final m = matches.toDouble();
    return (m / a.length + m / b.length + (m - transpositions / 2) / m) / 3;
  }
}

class _GuideIndex {
  final Map<String, XmltvChannel> byId;
  final Map<String, XmltvChannel> byNormalizedName;

  const _GuideIndex({required this.byId, required this.byNormalizedName});
}

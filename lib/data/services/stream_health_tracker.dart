import 'dart:convert';

import 'package:get_it/get_it.dart';

import '../../preference/user_preferences.dart';
import '../models/playable_channel.dart';

/// 30.09, Sid: "historique de fiabilité" - per-source (keyed by streamUrl)
/// success/failure counts, persisted so Smart Channels' failover learns
/// over time which of a group's alternatives are actually worth trying
/// first instead of a blind round-robin. Concept inspired by clubTivi's
/// StreamHealthTracker (github.com/clubanderson/clubTivi, Apache 2.0 - see
/// THIRD_PARTY_NOTICES.md), reimplemented from scratch against Moonfin's
/// own PlayableChannel/preferences rather than ported - clubTivi's tracks
/// several other signals (latency, bitrate stability) this doesn't.
class StreamHealthTracker {
  final _prefs = GetIt.instance<UserPreferences>();

  Map<String, ({int success, int failure})> _read() {
    try {
      final raw = jsonDecode(_prefs.get(UserPreferences.iptvStreamHealth));
      if (raw is! Map) return {};
      return raw.map((key, value) {
        final v = value as Map;
        return MapEntry(key as String, (
          success: (v['s'] as num?)?.toInt() ?? 0,
          failure: (v['f'] as num?)?.toInt() ?? 0,
        ));
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, ({int success, int failure})> stats) {
    final encoded = stats.map(
      (key, v) => MapEntry(key, {'s': v.success, 'f': v.failure}),
    );
    return _prefs.set(UserPreferences.iptvStreamHealth, jsonEncode(encoded));
  }

  Future<void> recordSuccess(String streamUrl) async {
    final stats = _read();
    final current = stats[streamUrl] ?? (success: 0, failure: 0);
    stats[streamUrl] = (success: current.success + 1, failure: current.failure);
    await _write(stats);
  }

  Future<void> recordFailure(String streamUrl) async {
    final stats = _read();
    final current = stats[streamUrl] ?? (success: 0, failure: 0);
    stats[streamUrl] = (success: current.success, failure: current.failure + 1);
    await _write(stats);
  }

  /// Fraction of attempts that succeeded, or 0.5 (neutral - neither
  /// preferred nor avoided) for a source with no history yet.
  double reliabilityOf(String streamUrl) {
    final stats = _read()[streamUrl];
    if (stats == null || (stats.success + stats.failure) == 0) return 0.5;
    return stats.success / (stats.success + stats.failure);
  }

  /// [alternatives] sorted best-reliability-first, ties broken by original
  /// order (so a group with no history at all keeps its configured
  /// primary-first order, same as before this existed).
  List<PlayableChannel> orderByReliability(List<PlayableChannel> alternatives) {
    final indexed = alternatives.indexed.toList();
    indexed.sort((a, b) {
      final scoreA = reliabilityOf(a.$2.streamUrl);
      final scoreB = reliabilityOf(b.$2.streamUrl);
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      return a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }
}

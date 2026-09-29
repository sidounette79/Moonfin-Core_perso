import 'dart:async';

import 'package:dio/dio.dart';

/// 29-30.09, Sid: Emby's TVDB plugin only ever reads TVDB's base/default
/// record, never TVDB's own dedicated `/translations/{lang}` endpoint - so
/// an item's overview (sometimes even its name) can come back English even
/// on a library correctly set to French. Confirmed live: Sofa (a separate
/// app on the same stack) shows the right French text for the same title.
///
/// Sofa already solves this for its own pages: it fetches TMDB with
/// `language=fr-FR` by default, then layers an optional TVDB French
/// translation on top when TVDB has one. Rather than duplicate that TVDB/
/// TMDB client (and a secret API key) inside this APK, Moonfin just asks
/// Sofa for the same resolved text, keyed by the tmdbId Emby already
/// exposes on every item via ProviderIds.Tmdb - see the Sofa-side
/// counterpart, apps/server/src/routes/french-overview.ts.
class SofaRepository {
  // Sid's own Sofa instance - this is a personal fork with one fixed
  // server, not a general-purpose setting.
  static const _baseUrl = 'https://sofa.sidounette.ch';

  final _dio = Dio();
  final _cache = <String, ({String? name, String? overview})?>{};
  final _pending = <String, Completer<({String? name, String? overview})?>>{};

  Future<({String? name, String? overview})?> getFrenchOverview({
    required String tmdbId,
    required String type,
    int? season,
    int? episode,
  }) async {
    final cacheKey = '$type:$tmdbId:${season ?? ''}:${episode ?? ''}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    final existing = _pending[cacheKey];
    if (existing != null) return existing.future;

    final completer = Completer<({String? name, String? overview})?>();
    _pending[cacheKey] = completer;

    try {
      final response = await _dio.get(
        '$_baseUrl/api/french-overview',
        queryParameters: {
          'tmdbId': tmdbId,
          'type': type,
          'season': ?season,
          'episode': ?episode,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final data = response.data;
      ({String? name, String? overview})? result;
      if (data is Map) {
        final name = data['name'] as String?;
        final overview = data['overview'] as String?;
        if ((name != null && name.isNotEmpty) ||
            (overview != null && overview.isNotEmpty)) {
          result = (name: name, overview: overview);
        }
      }
      _cache[cacheKey] = result;
      completer.complete(result);
      return result;
    } catch (_) {
      _cache[cacheKey] = null;
      completer.complete(null);
      return null;
    } finally {
      _pending.remove(cacheKey);
    }
  }

  void dispose() {
    _dio.close(force: true);
  }
}

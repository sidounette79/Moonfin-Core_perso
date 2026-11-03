import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../../preference/bazarr_preferences.dart';
import '../models/aggregated_item.dart';

const Map<String, String> _bazarrErrorMessages = {
  'series_not_found': 'Bazarr: cette série n\'est pas connue de Bazarr.',
  'episode_not_found': 'Bazarr: cet épisode n\'est pas connu de Bazarr.',
  'movie_not_found': 'Bazarr: ce film n\'est pas connu de Bazarr.',
  'missing_tvdb_id': 'Bazarr: identifiant TVDB introuvable pour cette série.',
  'missing_imdb_id': 'Bazarr: identifiant IMDB introuvable pour ce film.',
  'missing_episode_info': 'Bazarr: numéro de saison/épisode manquant.',
  'unsupported_item_type': 'Bazarr: type de contenu non pris en charge.',
};

/// A user-facing French message for a [BazarrDownloadResult.error] code,
/// shared by every screen that calls [BazarrService.downloadSubtitlesForItem]
/// so the three call sites don't each keep their own copy of this map.
String bazarrErrorMessage(String? code) {
  if (code == null) return 'Bazarr: aucun sous-titre trouvé.';
  return _bazarrErrorMessages[code] ?? 'Bazarr: échec ($code).';
}

/// Outcome of a two-language (fr+en) subtitle download request, so the UI
/// can tell "both found", "only one found" and "neither found" apart
/// instead of a single pass/fail.
class BazarrDownloadResult {
  const BazarrDownloadResult({
    required this.frenchDownloaded,
    required this.englishDownloaded,
    this.error,
  });

  final bool frenchDownloaded;
  final bool englishDownloaded;
  final String? error;

  bool get anyDownloaded => frenchDownloaded || englishDownloaded;
}

/// Direct client for a Bazarr instance (URL + API key, see
/// BazarrPreferences) - deliberately NOT routed through Emby or a
/// server-side proxy. Sid: "j'ai plein dans bazarr que je peux ajouter
/// facilement par rapport à emby... donc le mien c'est lien direct vers
/// bazarr."
///
/// Bazarr identifies a show by its own sonarrSeriesId/sonarrEpisodeId and
/// a movie by radarrId - none of which Emby knows about. The mapping used
/// here goes through tvdbId (series) / imdbId (movies), the same provider
/// ids Emby already exposes on every item (`ProviderIds`), since Bazarr's
/// `/api/series` and `/api/movies` list endpoints only accept filtering by
/// their own internal id, not by tvdb/imdb - so finding a match means
/// fetching the full list once and matching client-side. Fine for a
/// one-off "find subtitles" action, not meant to be called often.
///
/// Unlike Emby's /RemoteSearch/Subtitles (which returns a list of results
/// for the user to pick from), Bazarr's own `PATCH .../subtitles`
/// endpoint picks the best match itself (its own provider scoring) and
/// downloads it directly - no list, no manual choice. Sid: "on part sur
/// choix automatique et on verra à l'usage."
class BazarrService {
  BazarrService(this._prefs) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (_) => true,
      ),
    );
  }

  final BazarrPreferences _prefs;
  late final Dio _dio;

  bool get isConfigured =>
      _prefs.enabled &&
      _prefs.serverUrl.trim().isNotEmpty &&
      _prefs.apiKey.trim().isNotEmpty;

  String get _baseUrl =>
      _prefs.serverUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Options get _authOptions =>
      Options(headers: {'X-API-KEY': _prefs.apiKey.trim()});

  Future<bool> testConnection() async {
    if (!isConfigured) return false;
    try {
      final response = await _dio.get(
        '$_baseUrl/api/system/status',
        options: _authOptions,
      );
      final ok = response.statusCode == 200;
      await _prefs.setLastConnectionSuccess(ok);
      return ok;
    } catch (e) {
      await _prefs.setLastConnectionSuccess(false);
      return false;
    }
  }

  Future<int?> _findSeriesIdByTvdbId(int tvdbId) async {
    final response = await _dio.get(
      '$_baseUrl/api/series',
      queryParameters: {'length': -1},
      options: _authOptions,
    );
    if (response.statusCode != 200) return null;
    final data = (response.data is Map) ? response.data['data'] : null;
    if (data is! List) return null;
    for (final raw in data) {
      if (raw is Map && raw['tvdbId'] == tvdbId) {
        return (raw['sonarrSeriesId'] as num?)?.toInt();
      }
    }
    return null;
  }

  Future<int?> _findEpisodeId(
    int sonarrSeriesId, {
    required int season,
    required int episode,
  }) async {
    final response = await _dio.get(
      '$_baseUrl/api/episodes',
      queryParameters: {'seriesid[]': sonarrSeriesId},
      options: _authOptions,
    );
    if (response.statusCode != 200) return null;
    final data = (response.data is Map) ? response.data['data'] : null;
    if (data is! List) return null;
    for (final raw in data) {
      if (raw is Map &&
          raw['season'] == season &&
          raw['episode'] == episode) {
        return (raw['sonarrEpisodeId'] as num?)?.toInt();
      }
    }
    return null;
  }

  Future<int?> _findMovieIdByImdbId(String imdbId) async {
    final response = await _dio.get(
      '$_baseUrl/api/movies',
      queryParameters: {'length': -1},
      options: _authOptions,
    );
    if (response.statusCode != 200) return null;
    final data = (response.data is Map) ? response.data['data'] : null;
    if (data is! List) return null;
    for (final raw in data) {
      if (raw is Map && raw['imdbId'] == imdbId) {
        return (raw['radarrId'] as num?)?.toInt();
      }
    }
    return null;
  }

  Future<bool> _downloadEpisodeSubtitle({
    required int seriesId,
    required int episodeId,
    required String language,
  }) async {
    final response = await _dio.patch(
      '$_baseUrl/api/episodes/subtitles',
      queryParameters: {
        'seriesid': seriesId,
        'episodeid': episodeId,
        'language': language,
        'forced': 'false',
        'hi': 'false',
      },
      options: _authOptions,
    );
    // Bazarr returns 204 on an actual download; some versions/paths also
    // answer 200 with no body when a request was accepted but nothing new
    // was found - treat only 204 as a real success, same as its own docs.
    return response.statusCode == 204;
  }

  Future<bool> _downloadMovieSubtitle({
    required int radarrId,
    required String language,
  }) async {
    final response = await _dio.patch(
      '$_baseUrl/api/movies/subtitles',
      queryParameters: {
        'radarrid': radarrId,
        'language': language,
        'forced': 'false',
        'hi': 'false',
      },
      options: _authOptions,
    );
    return response.statusCode == 204;
  }

  /// Finds the episode in Bazarr matching [tvdbId]/[season]/[episode] and
  /// downloads both French and English subtitles for it. Each language is
  /// attempted independently - one failing (or already present, Bazarr
  /// returns non-204 for "nothing to do") doesn't stop the other.
  Future<BazarrDownloadResult> downloadEpisodeSubtitles({
    required int tvdbId,
    required int season,
    required int episode,
  }) async {
    if (!isConfigured) {
      return const BazarrDownloadResult(
        frenchDownloaded: false,
        englishDownloaded: false,
        error: 'not_configured',
      );
    }
    try {
      final seriesId = await _findSeriesIdByTvdbId(tvdbId);
      if (seriesId == null) {
        return const BazarrDownloadResult(
          frenchDownloaded: false,
          englishDownloaded: false,
          error: 'series_not_found',
        );
      }
      final episodeId = await _findEpisodeId(
        seriesId,
        season: season,
        episode: episode,
      );
      if (episodeId == null) {
        return const BazarrDownloadResult(
          frenchDownloaded: false,
          englishDownloaded: false,
          error: 'episode_not_found',
        );
      }
      final fr = await _downloadEpisodeSubtitle(
        seriesId: seriesId,
        episodeId: episodeId,
        language: 'fr',
      );
      final en = await _downloadEpisodeSubtitle(
        seriesId: seriesId,
        episodeId: episodeId,
        language: 'en',
      );
      return BazarrDownloadResult(
        frenchDownloaded: fr,
        englishDownloaded: en,
      );
    } catch (e) {
      return BazarrDownloadResult(
        frenchDownloaded: false,
        englishDownloaded: false,
        error: e.toString(),
      );
    }
  }

  /// Finds the movie in Bazarr matching [imdbId] and downloads both French
  /// and English subtitles for it.
  Future<BazarrDownloadResult> downloadMovieSubtitles({
    required String imdbId,
  }) async {
    if (!isConfigured) {
      return const BazarrDownloadResult(
        frenchDownloaded: false,
        englishDownloaded: false,
        error: 'not_configured',
      );
    }
    try {
      final radarrId = await _findMovieIdByImdbId(imdbId);
      if (radarrId == null) {
        return const BazarrDownloadResult(
          frenchDownloaded: false,
          englishDownloaded: false,
          error: 'movie_not_found',
        );
      }
      final fr = await _downloadMovieSubtitle(
        radarrId: radarrId,
        language: 'fr',
      );
      final en = await _downloadMovieSubtitle(
        radarrId: radarrId,
        language: 'en',
      );
      return BazarrDownloadResult(
        frenchDownloaded: fr,
        englishDownloaded: en,
      );
    } catch (e) {
      return BazarrDownloadResult(
        frenchDownloaded: false,
        englishDownloaded: false,
        error: e.toString(),
      );
    }
  }

  /// Resolves the right Bazarr lookup (tvdbId/season/episode for a TV
  /// episode, imdbId for a movie) from an Emby [item] and downloads fr+en
  /// subtitles. [client] is only used, for an episode, to fetch its parent
  /// series item - Emby puts the EPISODE's own tvdb id on `item.providerIds`,
  /// never the series', so that id has to come from a separate call on
  /// `item.seriesId` rather than from the episode item itself.
  Future<BazarrDownloadResult> downloadSubtitlesForItem({
    required MediaServerClient client,
    required AggregatedItem item,
  }) async {
    if (!isConfigured) {
      return const BazarrDownloadResult(
        frenchDownloaded: false,
        englishDownloaded: false,
        error: 'not_configured',
      );
    }
    if (item.type == 'Movie') {
      final imdbId = item.imdbId;
      if (imdbId == null || imdbId.isEmpty) {
        return const BazarrDownloadResult(
          frenchDownloaded: false,
          englishDownloaded: false,
          error: 'missing_imdb_id',
        );
      }
      return downloadMovieSubtitles(imdbId: imdbId);
    }
    if (item.type == 'Episode') {
      final season = item.parentIndexNumber;
      final episode = item.indexNumber;
      final seriesId = item.seriesId;
      if (season == null || episode == null || seriesId == null) {
        return const BazarrDownloadResult(
          frenchDownloaded: false,
          englishDownloaded: false,
          error: 'missing_episode_info',
        );
      }
      int? tvdbId;
      try {
        final seriesData = await client.itemsApi.getItem(seriesId);
        final seriesItem = AggregatedItem(
          id: seriesId,
          serverId: item.serverId,
          rawData: seriesData,
        );
        tvdbId = int.tryParse(seriesItem.tvdbId ?? '');
      } catch (_) {}
      if (tvdbId == null) {
        return const BazarrDownloadResult(
          frenchDownloaded: false,
          englishDownloaded: false,
          error: 'missing_tvdb_id',
        );
      }
      return downloadEpisodeSubtitles(
        tvdbId: tvdbId,
        season: season,
        episode: episode,
      );
    }
    return const BazarrDownloadResult(
      frenchDownloaded: false,
      englishDownloaded: false,
      error: 'unsupported_item_type',
    );
  }

  void close() => _dio.close();
}

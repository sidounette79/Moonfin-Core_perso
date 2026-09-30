import 'package:dio/dio.dart';

import '../models/xtream_models.dart';

/// 30.09: talks directly to a Xtream Codes IPTV provider's player_api.php,
/// bypassing Emby entirely - real shape confirmed live against Sid's own
/// account. Standard Xtream Codes REST API, not Moonfin/Emby-specific.
class XtreamRepository {
  final _dio = Dio();
  static const _timeout = Duration(seconds: 12);

  Future<XtreamAccountInfo?> getAccountInfo(XtreamProvider provider) async {
    try {
      final response = await _dio.getUri(
        provider.playerApiUri(const {}),
        options: Options(
          sendTimeout: _timeout,
          receiveTimeout: _timeout,
        ),
      );
      final data = response.data;
      if (data is! Map) return null;
      return XtreamAccountInfo.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<List<XtreamCategory>> getLiveCategories(
    XtreamProvider provider,
  ) async {
    try {
      final response = await _dio.getUri(
        provider.playerApiUri(const {'action': 'get_live_categories'}),
        options: Options(sendTimeout: _timeout, receiveTimeout: _timeout),
      );
      final data = response.data;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => XtreamCategory.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<XtreamChannel>> getLiveStreams(
    XtreamProvider provider, {
    String? categoryId,
  }) async {
    try {
      final response = await _dio.getUri(
        provider.playerApiUri({
          'action': 'get_live_streams',
          'category_id': ?categoryId,
        }),
        options: Options(sendTimeout: _timeout, receiveTimeout: _timeout),
      );
      final data = response.data;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => XtreamChannel.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<XtreamEpgEntry>> getShortEpg(
    XtreamProvider provider,
    int streamId,
  ) async {
    try {
      final response = await _dio.getUri(
        provider.playerApiUri({
          'action': 'get_short_epg',
          'stream_id': streamId.toString(),
        }),
        options: Options(sendTimeout: _timeout, receiveTimeout: _timeout),
      );
      final data = response.data;
      if (data is! Map) return const [];
      final listings = data['epg_listings'];
      if (listings is! List) return const [];
      return listings
          .whereType<Map>()
          .map((e) => XtreamEpgEntry.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void dispose() {
    _dio.close(force: true);
  }
}

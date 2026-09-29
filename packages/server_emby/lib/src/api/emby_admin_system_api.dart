import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

// 29.09: same-lineage feature, Emby's REST shape matches Jellyfin's almost
// exactly for the core system endpoints (System/Configuration, restart/
// shutdown, logs, activity log, localization) - not live-tested against a
// real Emby admin token from here, needs a real device test.
//
// Two methods (upload/deleteSplashscreen) throw a specific UnsupportedError
// rather than guess a wrong path: Jellyfin's Branding/Splashscreen custom
// login image is a Jellyfin-only feature added independently, no confident
// Emby equivalent exists.
class EmbyAdminSystemApi implements AdminSystemApi {
  final Dio _dio;

  EmbyAdminSystemApi(this._dio);

  @override
  Future<Map<String, dynamic>> getServerConfiguration() async {
    final response = await _dio.get('/System/Configuration');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> updateServerConfiguration(Map<String, dynamic> config) async {
    await _dio.post('/System/Configuration', data: config);
  }

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async {
    // 29.09, Sid, real device test: "network" threw a real Emby-side C#
    // exception ("Sequence contains no matching element") - confirmed via
    // Emby's own web dashboard that the data exists and is editable there,
    // so this isn't a missing-feature case. Unlike Jellyfin, which split
    // network settings into their own named configuration section (added
    // later, a Jellyfin-only architecture change), Emby never split
    // network settings out at all - they're just part of the single root
    // ServerConfiguration returned by plain /System/Configuration. The
    // screen that calls this (admin_networking_screen.dart) only reads a
    // fixed set of known keys (EnableRemoteAccess, HttpServerPortNumber,
    // LocalNetworkAddresses, ...) from whatever map it gets back, so
    // handing it the full config here is safe - extra unrelated fields are
    // simply never touched.
    if (key == 'network') {
      final response = await _dio.get('/System/Configuration');
      return response.data as Map<String, dynamic>;
    }
    final response = await _dio.get('/System/Configuration/$key');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> updateNamedConfiguration(
    String key,
    Map<String, dynamic> config,
  ) async {
    // Mirrors getNamedConfiguration above: Emby has no separate "network"
    // section to POST to, so this writes the (already-full, only
    // known-fields-edited) config object back to the single root
    // configuration endpoint instead.
    if (key == 'network') {
      await _dio.post('/System/Configuration', data: config);
      return;
    }
    await _dio.post('/System/Configuration/$key', data: config);
  }

  @override
  Future<StorageInfo> getStorageInfo() async {
    final response = await _dio.get('/System/Info/Storage');
    return StorageInfo.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> restartServer() async {
    await _dio.post('/System/Restart');
  }

  @override
  Future<void> shutdownServer() async {
    await _dio.post('/System/Shutdown');
  }

  @override
  Future<List<LogFileInfo>> getLogFiles() async {
    final response = await _dio.get('/System/Logs');
    return (response.data as List<dynamic>)
        .map((e) => LogFileInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<String> getLogFileContent(String name) async {
    final response = await _dio.get(
      '/System/Logs/Log',
      queryParameters: {'name': name},
    );
    return response.data as String;
  }

  @override
  Future<ActivityLogResult> getActivityLog({
    int? startIndex,
    int? limit,
    bool? hasUserId,
    DateTime? minDate,
  }) async {
    final params = <String, dynamic>{};
    if (startIndex != null) params['startIndex'] = startIndex;
    if (limit != null) params['limit'] = limit;
    if (hasUserId != null) params['hasUserId'] = hasUserId;
    if (minDate != null) params['minDate'] = minDate.toUtc().toIso8601String();
    final response = await _dio.get(
      '/System/ActivityLog/Entries',
      queryParameters: params,
    );
    return ActivityLogResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> _getLocalizationList(String path) async {
    final response = await _dio.get(path);
    return (response.data as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getCultures() =>
      _getLocalizationList('/Localization/Cultures');

  @override
  Future<List<Map<String, dynamic>>> getCountries() =>
      _getLocalizationList('/Localization/Countries');

  @override
  Future<List<Map<String, dynamic>>> getLocalizationOptions() =>
      _getLocalizationList('/Localization/Options');

  @override
  Future<List<Map<String, dynamic>>> getParentalRatings() =>
      _getLocalizationList('/Localization/ParentalRatings');

  @override
  Future<List<Map<String, dynamic>>> getAuthProviders() =>
      _getLocalizationList('/Auth/Providers');

  @override
  Future<List<Map<String, dynamic>>> getPasswordResetProviders() =>
      _getLocalizationList('/Auth/PasswordResetProviders');

  @override
  Future<void> uploadSplashscreen(List<int> bytes, String contentType) async {
    throw UnsupportedError(
      'Custom splashscreen upload is a Jellyfin-only feature, no Emby equivalent',
    );
  }

  @override
  Future<void> deleteSplashscreen() async {
    throw UnsupportedError(
      'Custom splashscreen upload is a Jellyfin-only feature, no Emby equivalent',
    );
  }

  @override
  Future<Map<String, dynamic>> getItemCounts() async {
    final response = await _dio.get('/Items/Counts');
    return response.data as Map<String, dynamic>;
  }
}

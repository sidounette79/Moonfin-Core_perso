import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

// 29.09: unlike the other admin APIs, backup/restore is NOT a confidently
// shared feature - Emby's stock server has historically had no built-in
// backup admin endpoint the way Jellyfin added one, but this isn't fully
// certain either. Same defensive multi-path-fallback pattern Jellyfin's own
// JellyfinAdminBackupApi already uses for this exact reason: try every
// plausible path, only give up once all of them 404/405/501. If Emby truly
// has no backup feature, every call here will surface a clean error rather
// than silently doing nothing. Not live-tested from here, needs a real
// device test.
class EmbyAdminBackupApi implements AdminBackupApi {
  final Dio _dio;

  EmbyAdminBackupApi(this._dio);

  @override
  Future<List<Map<String, dynamic>>> getBackups() async {
    final response = await _getWithFallback([
      '/Backup',
      '/System/Backups',
      '/Backups',
      '/Environment/Backups',
    ]);

    final data = response.data;
    if (data is List) {
      return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (data is Map<String, dynamic>) {
      final items = data['Items'] ?? data['items'] ?? data['Backups'] ?? data['backups'];
      if (items is List) {
        return items.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> createBackup([
    Map<String, dynamic>? options,
  ]) async {
    final response = await _postWithFallback(
      [
        '/Backup/Create',
        '/System/Backups',
        '/System/Backups/Create',
        '/Backups',
        '/Environment/Backups/Create',
      ],
      data: options,
    );

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    return const {};
  }

  @override
  Future<void> restoreBackup(String backupPath) async {
    await _postWithFallback(
      [
        '/Backup/Restore',
        '/System/Backups/Restore',
        '/Backups/Restore',
        '/Environment/Backups/Restore',
      ],
      data: {'ArchiveFileName': backupPath},
    );
  }

  @override
  Future<Map<String, dynamic>> getBackupManifest(String backupPath) async {
    final response = await _getWithFallback(
      [
        '/Backup/Manifest',
        '/System/Backups/Manifest',
        '/Backups/Manifest',
        '/Environment/Backups/Manifest',
      ],
      queryParameters: {'path': backupPath},
    );

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is List) {
      return {'Items': data};
    }
    return const {};
  }

  Future<Response<dynamic>> _getWithFallback(
    List<String> paths, {
    Map<String, dynamic>? queryParameters,
  }) async {
    DioException? lastDioError;
    for (final path in paths) {
      try {
        return await _dio.get(path, queryParameters: queryParameters);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 404 || status == 405 || status == 501) {
          lastDioError = e;
          continue;
        }
        rethrow;
      }
    }
    throw lastDioError ?? StateError('No backup endpoint responded');
  }

  Future<Response<dynamic>> _postWithFallback(
    List<String> paths, {
    Map<String, dynamic>? queryParameters,
    Object? data,
  }) async {
    DioException? lastDioError;
    for (final path in paths) {
      try {
        return await _dio.post(
          path,
          queryParameters: queryParameters,
          data: data,
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 404 || status == 405 || status == 501) {
          lastDioError = e;
          continue;
        }
        rethrow;
      }
    }
    throw lastDioError ?? StateError('No backup endpoint responded');
  }
}

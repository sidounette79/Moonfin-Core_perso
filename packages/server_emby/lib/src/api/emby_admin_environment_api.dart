import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

// 29.09: Environment/* (folder picker) is core, stable, identical in Emby -
// not live-tested from here, needs a real device test.
class EmbyAdminEnvironmentApi implements AdminEnvironmentApi {
  final Dio _dio;

  EmbyAdminEnvironmentApi(this._dio);

  @override
  Future<List<Map<String, dynamic>>> getDirectoryContents(
    String path, {
    bool? includeFiles,
    bool? includeDirectories,
  }) async {
    final response = await _dio.get(
      '/Environment/DirectoryContents',
      queryParameters: {
        'path': path,
        'includeFiles': ?includeFiles,
        'includeDirectories': ?includeDirectories,
      },
    );
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  @override
  Future<void> validatePath(String path) async {
    await _dio.post(
      '/Environment/ValidatePath',
      data: {'ValidateWritable': false, 'Path': path},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getDrives() async {
    final response = await _dio.get('/Environment/Drives');
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  @override
  Future<String?> getParentPath(String path) async {
    final response = await _dio.get(
      '/Environment/ParentPath',
      queryParameters: {'path': path},
    );
    return response.data as String?;
  }
}

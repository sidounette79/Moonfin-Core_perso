import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

// 29.09: /Plugins, /Plugins/{id}/Configuration, /Packages* are core, stable,
// identical in Emby. Two real differences from Jellyfin handled here:
// - Emby uninstalls a plugin by GUID alone (DELETE /Plugins/{id}), not the
//   Jellyfin-added /{id}/{version} form - tried first, with the Jellyfin
//   shape as a fallback in case a given Emby version does support it.
// - Emby has no dedicated /Repositories list endpoint (a newer Jellyfin
//   addition) - plugin repository URLs live in ServerConfiguration's own
//   PluginRepositories field instead, so get/setRepositories round-trip
//   through /System/Configuration.
// Enable/disable is attempted via the Jellyfin-shaped endpoint since no
// confident Emby equivalent is known; a 404 there means Emby genuinely
// doesn't support toggling a plugin without uninstalling it.
// Not live-tested from here, needs a real device test.
class EmbyAdminPluginsApi implements AdminPluginsApi {
  final Dio _dio;

  EmbyAdminPluginsApi(this._dio);

  @override
  Future<List<PluginInfo>> getInstalledPlugins() async {
    final response = await _dio.get('/Plugins');
    return (response.data as List<dynamic>)
        .map((e) => PluginInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> enablePlugin(String pluginId, String version) async {
    await _dio.post('/Plugins/$pluginId/$version/Enable');
  }

  @override
  Future<void> disablePlugin(String pluginId, String version) async {
    await _dio.post('/Plugins/$pluginId/$version/Disable');
  }

  @override
  Future<void> uninstallPlugin(String pluginId, String version) async {
    try {
      await _dio.delete('/Plugins/$pluginId');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        await _dio.delete('/Plugins/$pluginId/$version');
        return;
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getPluginConfiguration(String pluginId) async {
    final response = await _dio.get('/Plugins/$pluginId/Configuration');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> updatePluginConfiguration(
      String pluginId, Map<String, dynamic> config) async {
    await _dio.post('/Plugins/$pluginId/Configuration', data: config);
  }

  @override
  Future<List<PackageInfo>> getAvailablePackages() async {
    final response = await _dio.get('/Packages');
    return (response.data as List<dynamic>)
        .map((e) => PackageInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PackageInfo?> getPackageInfo(String name,
      {String? assemblyGuid}) async {
    final response = await _dio.get(
      '/Packages/${Uri.encodeComponent(name)}',
      queryParameters: {
        'assemblyGuid': ?assemblyGuid,
      },
    );
    if (response.statusCode == 404) return null;
    return PackageInfo.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> installPackage(
    String name, {
    String? assemblyGuid,
    String? version,
    String? repositoryUrl,
  }) async {
    await _dio.post(
      '/Packages/Installed/${Uri.encodeComponent(name)}',
      queryParameters: {
        'assemblyGuid': ?assemblyGuid,
        'version': ?version,
        'repositoryUrl': ?repositoryUrl,
      },
    );
  }

  @override
  Future<void> cancelPackageInstallation(String packageId) async {
    await _dio.delete('/Packages/Installing/$packageId');
  }

  @override
  Future<List<RepositoryInfo>> getRepositories() async {
    final response = await _dio.get('/System/Configuration');
    final config = response.data as Map<String, dynamic>;
    final repos = config['PluginRepositories'];
    if (repos is! List) return const [];
    return repos
        .whereType<Map>()
        .map((e) => RepositoryInfo.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> setRepositories(List<RepositoryInfo> repositories) async {
    final response = await _dio.get('/System/Configuration');
    final config = Map<String, dynamic>.from(
      response.data as Map<String, dynamic>,
    );
    config['PluginRepositories'] =
        repositories.map((r) => r.toJson()).toList();
    await _dio.post('/System/Configuration', data: config);
  }
}

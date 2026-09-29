import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

// 29.09, Sid: first of the 11 admin APIs Emby support never implemented
// (see JellyfinAdminUsersApi for the reference shape this mirrors - the
// whole admin Users screen/add/edit/delete UI already exists and was only
// ever wired to Jellyfin). Emby forked from the same lineage Jellyfin
// later forked again from, so its user-management REST surface is the
// same shape: /Users, /Users/New, /Users/{id}, /Users/{id}/Policy,
// /Users/{id}/Password - all PascalCase bodies/params, matching every
// other Emby*Api file in this package (EmbyUsersApi's own working
// GET /Users/$userId is the same base convention). Not live-tested
// against a real Emby admin token from here - needs a real device test.
class EmbyAdminUsersApi implements AdminUsersApi {
  final Dio _dio;

  EmbyAdminUsersApi(this._dio);

  @override
  Future<List<ServerUser>> getUsers({bool? isDisabled, bool? isHidden}) async {
    final params = <String, dynamic>{};
    if (isDisabled != null) params['IsDisabled'] = isDisabled;
    if (isHidden != null) params['IsHidden'] = isHidden;
    final response = await _dio.get('/Users', queryParameters: params);
    return (response.data as List<dynamic>)
        .map((e) => ServerUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ServerUser> getUserById(String userId) async {
    final response = await _dio.get('/Users/$userId');
    return ServerUser.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<ServerUser> createUser(String name, String? password) async {
    final response = await _dio.post(
      '/Users/New',
      data: {
        'Name': name,
        'Password': ?password,
      },
    );
    return ServerUser.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteUser(String userId) async {
    await _dio.delete('/Users/$userId');
  }

  @override
  Future<void> updateUser(String userId, Map<String, dynamic> userData) async {
    await _dio.post(
      '/Users/$userId',
      data: {
        'Id': userId,
        'Name': userData['Name'],
        'Configuration': userData['Configuration'] ?? <String, dynamic>{},
      },
    );
  }

  @override
  Future<void> updateUserPolicy(
    String userId,
    Map<String, dynamic> policy,
  ) async {
    await _dio.post('/Users/$userId/Policy', data: policy);
  }

  @override
  Future<void> updateUserPassword(
    String userId, {
    String? newPassword,
    bool resetPassword = false,
  }) async {
    await _dio.post(
      '/Users/$userId/Password',
      data: {
        'Id': userId,
        'NewPw': ?newPassword,
        'ResetPassword': resetPassword,
      },
    );
  }
}

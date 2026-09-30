/// 30.09, Sid: "TiviMate-style" direct IPTV, bypassing Emby's own Live TV
/// entirely - she already has a real Xtream Codes provider (used server-side
/// by the Emby Xtream Tuner plugin too, but that's a separate integration;
/// this talks to the provider directly). Real API shape confirmed live
/// against her own account (player_api.php), not guessed from docs.
library;

import 'dart:convert';

class XtreamProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String username;
  final String password;

  const XtreamProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  /// Normalized, no trailing slash - every endpoint below assumes this.
  String get _cleanBaseUrl =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Uri playerApiUri(Map<String, String> params) => Uri.parse(_cleanBaseUrl)
      .replace(path: '/player_api.php', queryParameters: {
    'username': username,
    'password': password,
    ...params,
  });

  /// Direct stream URL - never goes through player_api.php, this is the
  /// actual media source handed to the player.
  String streamUrl(int streamId, {String ext = 'ts'}) =>
      '$_cleanBaseUrl/live/$username/$password/$streamId.$ext';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'username': username,
    'password': password,
  };

  factory XtreamProvider.fromJson(Map<String, dynamic> json) => XtreamProvider(
    id: json['id'] as String,
    name: json['name'] as String,
    baseUrl: json['baseUrl'] as String,
    username: json['username'] as String,
    password: json['password'] as String,
  );
}

class XtreamAccountInfo {
  final String status;
  final DateTime? expiresAt;
  final int maxConnections;
  final int activeConnections;

  const XtreamAccountInfo({
    required this.status,
    required this.expiresAt,
    required this.maxConnections,
    required this.activeConnections,
  });

  factory XtreamAccountInfo.fromJson(Map<String, dynamic> json) {
    final info = json['user_info'] as Map<String, dynamic>? ?? const {};
    final expRaw = info['exp_date'] as String?;
    final expSeconds = expRaw != null ? int.tryParse(expRaw) : null;
    return XtreamAccountInfo(
      status: info['status'] as String? ?? 'Unknown',
      expiresAt: expSeconds != null
          ? DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000)
          : null,
      maxConnections: int.tryParse(info['max_connections'] as String? ?? '') ?? 1,
      activeConnections: int.tryParse(info['active_cons'] as String? ?? '') ?? 0,
    );
  }
}

class XtreamCategory {
  final String id;
  final String name;

  const XtreamCategory({required this.id, required this.name});

  factory XtreamCategory.fromJson(Map<String, dynamic> json) => XtreamCategory(
    id: json['category_id'].toString(),
    name: json['category_name'] as String? ?? '',
  );
}

class XtreamChannel {
  final int streamId;
  final String name;
  final String? iconUrl;
  final String categoryId;
  final String? epgChannelId;

  const XtreamChannel({
    required this.streamId,
    required this.name,
    required this.categoryId,
    this.iconUrl,
    this.epgChannelId,
  });

  factory XtreamChannel.fromJson(Map<String, dynamic> json) => XtreamChannel(
    streamId: (json['stream_id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    categoryId: json['category_id']?.toString() ?? '',
    iconUrl: (json['stream_icon'] as String?)?.trim().isNotEmpty == true
        ? json['stream_icon'] as String
        : null,
    epgChannelId: (json['epg_channel_id'] as String?)?.trim().isNotEmpty == true
        ? json['epg_channel_id'] as String
        : null,
  );
}

/// A single EPG entry, from get_short_epg - base64-encoded title/description
/// per the standard Xtream Codes API shape.
class XtreamEpgEntry {
  final String title;
  final DateTime start;
  final DateTime end;

  const XtreamEpgEntry({
    required this.title,
    required this.start,
    required this.end,
  });

  static String _decodeB64(String? value) {
    if (value == null || value.isEmpty) return '';
    try {
      return String.fromCharCodes(base64.decode(value));
    } catch (_) {
      return value;
    }
  }

  factory XtreamEpgEntry.fromJson(Map<String, dynamic> json) => XtreamEpgEntry(
    title: _decodeB64(json['title'] as String?),
    start: DateTime.tryParse(json['start'] as String? ?? '') ?? DateTime.now(),
    end: DateTime.tryParse(json['end'] as String? ?? '') ?? DateTime.now(),
  );
}

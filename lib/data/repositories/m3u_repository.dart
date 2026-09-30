import 'package:dio/dio.dart';

import '../models/m3u_provider.dart';
import '../models/playable_channel.dart';

/// 30.09: parses a plain M3U/M3U8 playlist - the standard #EXTINF-per-line
/// format most IPTV tools export, distinct from the Xtream Codes REST API
/// XtreamRepository talks to.
class M3uRepository {
  final _dio = Dio();
  static final _attrRegex = RegExp(r'([a-zA-Z-]+)="([^"]*)"');

  Future<List<PlayableChannel>> fetchChannels(M3uProvider provider) async {
    try {
      final response = await _dio.get<String>(
        provider.url,
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final body = response.data;
      if (body == null || body.isEmpty) return const [];
      return _parse(body, provider.name);
    } catch (_) {
      return const [];
    }
  }

  List<PlayableChannel> _parse(String body, String sourceName) {
    final lines = body.split(RegExp(r'\r?\n'));
    final channels = <PlayableChannel>[];

    String? pendingName;
    String? pendingLogo;
    String? pendingGroup;
    String? pendingTvgId;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        final attrs = <String, String>{
          for (final m in _attrRegex.allMatches(line)) m.group(1)!: m.group(2)!,
        };
        pendingLogo = attrs['tvg-logo'];
        pendingGroup = attrs['group-title'] ?? '';
        // 30.09: needed to match this channel against a separate XMLTV
        // guide (see EpgChannelMatcher) - tvg-name is deliberately not
        // captured here too, the channel's own display name (below) already
        // serves that role for the matcher's fuzzy-name fallback.
        pendingTvgId = attrs['tvg-id'];
        final commaIndex = line.lastIndexOf(',');
        pendingName = commaIndex >= 0
            ? line.substring(commaIndex + 1).trim()
            : null;
        continue;
      }

      if (line.startsWith('#')) continue;

      // Any other non-empty, non-comment line is a stream URL - the entry
      // that follows the #EXTINF line describing it.
      if (pendingName != null && pendingName.isNotEmpty) {
        channels.add(PlayableChannel(
          name: pendingName,
          streamUrl: line,
          sourceName: sourceName,
          iconUrl: (pendingLogo != null && pendingLogo.isNotEmpty)
              ? pendingLogo
              : null,
          groupTitle: pendingGroup ?? '',
          tvgId: (pendingTvgId != null && pendingTvgId.isNotEmpty)
              ? pendingTvgId
              : null,
        ));
      }
      pendingName = null;
      pendingLogo = null;
      pendingGroup = null;
      pendingTvgId = null;
    }

    return channels;
  }

  void dispose() {
    _dio.close(force: true);
  }
}

/// 30.09, Sid: added a raw M3U playlist as a second IPTV source alongside
/// Xtream Codes providers ("j'ai fait une m3u qui regroupe mes 3 listes...
/// rajoute [le support]"). Xtream channels and M3U entries have
/// fundamentally different shapes (Xtream needs provider+streamId to build
/// a URL; an M3U line already carries its own full URL) - this is the
/// common shape the channel list and player actually consume, so neither
/// has to know which source a given channel came from.
typedef EpgEntryData = ({String title, DateTime start, DateTime end});

class PlayableChannel {
  final String name;
  final String? iconUrl;
  final String streamUrl;
  final String sourceName;
  final String groupTitle;

  /// Null for a source with no EPG API (M3U) - Xtream channels get a real
  /// fetch closure from whoever built this entry.
  final Future<List<EpgEntryData>> Function()? fetchEpg;

  const PlayableChannel({
    required this.name,
    required this.streamUrl,
    required this.sourceName,
    this.iconUrl,
    this.groupTitle = '',
    this.fetchEpg,
  });
}

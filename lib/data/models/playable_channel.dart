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

  /// From the M3U entry's tvg-id attribute, if any - an M3U provider with an
  /// XMLTV guide URL matches against this first (see EpgChannelMatcher)
  /// before falling back to fuzzy name matching. Always null for Xtream
  /// channels, which get their EPG straight from the provider's API by
  /// stream ID instead.
  final String? tvgId;

  /// Null for a source with no EPG API and no matched XMLTV channel -
  /// Xtream channels get a real fetch closure from whoever built this
  /// entry, and so does an M3U channel once matched against its provider's
  /// XMLTV guide.
  final Future<List<EpgEntryData>> Function()? fetchEpg;

  const PlayableChannel({
    required this.name,
    required this.streamUrl,
    required this.sourceName,
    this.iconUrl,
    this.groupTitle = '',
    this.tvgId,
    this.fetchEpg,
  });

  /// Used to attach a [fetchEpg] closure once an M3U channel has been
  /// matched against its provider's XMLTV guide - the match only happens
  /// after the channel itself is already built (see EpgChannelMatcher).
  PlayableChannel withFetchEpg(
    Future<List<EpgEntryData>> Function() fetchEpg,
  ) => PlayableChannel(
    name: name,
    streamUrl: streamUrl,
    sourceName: sourceName,
    iconUrl: iconUrl,
    groupTitle: groupTitle,
    tvgId: tvgId,
    fetchEpg: fetchEpg,
  );
}

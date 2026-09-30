import '../services/epg_channel_matcher.dart';
import 'playable_channel.dart';

/// 30.09, Sid: "Smart Channels" - the same logical channel as it shows up
/// across different providers (Xtream accounts, M3U lists), grouped so a
/// stall on one source can fail over to another instead of just buffering
/// forever. Concept and priority-order behaviour adapted from clubTivi's
/// ColdFailoverEngine/CrossProviderMatcher (Apache 2.0, see
/// THIRD_PARTY_NOTICES.md) - grouped by normalized channel name here
/// rather than shared EPG id, since most of her channels have no XMLTV
/// match at all (no guide configured) and would otherwise never group.
class ChannelGroup {
  /// The grouping key (see EpgChannelMatcher.groupingKey) - not shown to
  /// the user, just what ties the alternatives together.
  final String key;

  /// Every source's copy of this channel, in the order
  /// [StreamFailoverController] tries them - whichever was added first (the
  /// order providers are configured in) stays primary.
  final List<PlayableChannel> alternatives;

  const ChannelGroup({required this.key, required this.alternatives});

  PlayableChannel get primary => alternatives.first;

  static List<ChannelGroup> groupChannels(List<PlayableChannel> channels) {
    final byKey = <String, List<PlayableChannel>>{};
    for (final channel in channels) {
      final key = EpgChannelMatcher.groupingKey(channel.name);
      byKey.putIfAbsent(key, () => []).add(channel);
    }
    return [
      for (final entry in byKey.entries)
        ChannelGroup(key: entry.key, alternatives: entry.value),
    ];
  }
}

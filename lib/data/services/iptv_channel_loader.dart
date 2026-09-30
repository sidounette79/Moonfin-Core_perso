import 'package:get_it/get_it.dart';

import '../models/playable_channel.dart';
import '../repositories/m3u_repository.dart';
import '../repositories/xmltv_repository.dart';
import '../repositories/xtream_repository.dart';
import 'epg_channel_matcher.dart';
import '../../preference/user_preferences.dart';

/// 30.09: the full "every configured IPTV channel, across every source"
/// load - originally inline in XtreamChannelsScreen, pulled out once the
/// EPG grid screen needed the exact same list. Xtream channels get their
/// EPG from the provider's own API; M3U channels get theirs by matching
/// against their provider's XMLTV guide, if it has one (see
/// EpgChannelMatcher) - both end up as the same PlayableChannel shape with
/// a working fetchEpg, so neither screen needs to know which source a
/// channel came from.
class IptvChannelLoader {
  final _prefs = GetIt.instance<UserPreferences>();
  final _xtreamRepo = GetIt.instance<XtreamRepository>();
  final _m3uRepo = GetIt.instance<M3uRepository>();
  final _xmltvRepo = GetIt.instance<XmltvRepository>();

  bool get hasAnyProvider =>
      _prefs.getXtreamProviders().isNotEmpty ||
      _prefs.getM3uProviders().isNotEmpty;

  Future<List<PlayableChannel>> load() async {
    final xtreamProviders = _prefs.getXtreamProviders();
    final m3uProviders = _prefs.getM3uProviders();
    final selectedByProvider = _prefs.getXtreamSelectedCategoryIds();
    final excludedByProvider = _prefs.getXtreamExcludedChannelIds();
    final channels = <PlayableChannel>[];

    for (final provider in xtreamProviders) {
      final selectedCategoryIds = selectedByProvider[provider.id] ?? const [];
      if (selectedCategoryIds.isEmpty) continue;
      final excludedChannelIds =
          excludedByProvider[provider.id]?.toSet() ?? const {};

      final categories = await _xtreamRepo.getLiveCategories(provider);
      final categoryNames = {for (final c in categories) c.id: c.name};

      for (final categoryId in selectedCategoryIds) {
        final streams = await _xtreamRepo.getLiveStreams(
          provider,
          categoryId: categoryId,
        );
        for (final stream in streams) {
          if (excludedChannelIds.contains(stream.streamId.toString())) {
            continue;
          }
          channels.add(
            PlayableChannel(
              name: stream.name,
              iconUrl: stream.iconUrl,
              streamUrl: provider.streamUrl(stream.streamId),
              sourceName: provider.name,
              groupTitle: categoryNames[categoryId] ?? categoryId,
              fetchEpg: () async {
                final listings = await _xtreamRepo.getShortEpg(
                  provider,
                  stream.streamId,
                );
                return [
                  for (final e in listings)
                    (title: e.title, start: e.start, end: e.end),
                ];
              },
            ),
          );
        }
      }
    }

    for (final provider in m3uProviders) {
      final parsed = await _m3uRepo.fetchChannels(provider);

      final epgUrl = provider.epgUrl;
      if (epgUrl == null || epgUrl.isEmpty) {
        channels.addAll(parsed);
        continue;
      }

      // One guide fetch per provider, matched against every one of its
      // channels - not one fetch per channel, which would mean
      // re-downloading and re-parsing what's often a multi-MB XMLTV feed
      // dozens of times over.
      final guide = await _xmltvRepo.fetchGuide(epgUrl);
      if (guide == null) {
        channels.addAll(parsed);
        continue;
      }

      for (final channel in parsed) {
        final match = EpgChannelMatcher.match(channel, guide);
        if (match == null) {
          channels.add(channel);
          continue;
        }
        channels.add(
          channel.withFetchEpg(() async {
            final programmes = EpgChannelMatcher.programmesFor(
              match.channel,
              guide,
            );
            return [
              for (final p in programmes)
                (title: p.title, start: p.start, end: p.stop),
            ];
          }),
        );
      }
    }

    return channels;
  }
}

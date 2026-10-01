import 'package:server_core/server_core.dart';

import '../models/aggregated_item.dart';

/// Detects a "forgotten viewing front": an earlier, still-unwatched run of
/// episodes in a series whose NextUp entry has jumped ahead to a more
/// recent episode. This happens when Emby/Jellyfin's NextUp algorithm only
/// tracks a single "front" per series — if the user watches a later episode
/// out of order (e.g. revisiting one episode after seeing a documentary
/// about it) before finishing an earlier run, NextUp forgets the earlier
/// unfinished run entirely and anchors on the later one instead.
///
/// For each NextUp item that is an Episode, this fetches the series' full
/// episode list and looks for the earliest unwatched episode that has at
/// least one watched episode somewhere after it in viewing order — that is
/// the signature of an abandoned front. If that episode differs from the
/// one NextUp already returned for the series, a synthetic [AggregatedItem]
/// pointing to it is appended to the list, flagged via
/// `rawData['_isForgottenFront'] = true` so the UI can surface it
/// distinctly (e.g. a "reprise oubliée" badge) instead of silently
/// replacing the normal NextUp card.
Future<List<AggregatedItem>> appendForgottenViewingFronts(
  List<AggregatedItem> nextUpItems,
  MediaServerClient client,
) async {
  final episodeItems = nextUpItems.where((item) => item.type == 'Episode');
  final seriesIds = episodeItems
      .map((item) => item.rawData['SeriesId']?.toString())
      .where((id) => id != null && id.isNotEmpty)
      .cast<String>()
      .toSet();

  if (seriesIds.isEmpty) return nextUpItems;

  final extraItems = <AggregatedItem>[];

  for (final seriesId in seriesIds) {
    try {
      final nextUpItem = episodeItems.firstWhere(
        (item) => item.rawData['SeriesId']?.toString() == seriesId,
      );

      final episodesRes = await client.itemsApi.getItems(
        parentId: seriesId,
        includeItemTypes: const ['Episode'],
        recursive: true,
        sortBy: 'ParentIndexNumber,IndexNumber',
        sortOrder: 'Ascending',
        fields: 'UserData',
      );
      final episodes = (episodesRes['Items'] as List? ?? [])
          .whereType<Map>()
          .toList();
      if (episodes.isEmpty) continue;

      final playedFlags = episodes
          .map((e) => (e['UserData']?['Played'] as bool?) ?? false)
          .toList();

      // The earliest unwatched episode that has a later *watched* episode
      // is an abandoned front: the user watched ahead and skipped it.
      int? gapIndex;
      for (var i = 0; i < episodes.length; i++) {
        if (playedFlags[i]) continue;
        if (playedFlags.skip(i + 1).any((played) => played)) {
          gapIndex = i;
          break;
        }
      }
      if (gapIndex == null) continue;

      final gapEpisode = episodes[gapIndex];
      final gapEpisodeId = gapEpisode['Id']?.toString();
      if (gapEpisodeId == null || gapEpisodeId == nextUpItem.id) continue;

      final rawData = Map<String, dynamic>.from(gapEpisode);
      rawData['_isForgottenFront'] = true;
      // Forces this synthetic entry to sort first wherever NextUp items are
      // later re-sorted by UserData.LastPlayedDate (e.g. the aggregated
      // multi-server row) — without it, the missing real LastPlayedDate
      // would sort it last and `.take(limit)` could silently drop it.
      final userData = Map<String, dynamic>.from(
        rawData['UserData'] as Map? ?? {},
      );
      userData['LastPlayedDate'] = DateTime.now().toIso8601String();
      rawData['UserData'] = userData;
      extraItems.add(
        AggregatedItem(
          id: gapEpisodeId,
          serverId: nextUpItem.serverId,
          rawData: rawData,
        ),
      );
    } catch (_) {
      // Best-effort enrichment: skip this series on any error (e.g. the
      // series was removed, or the server rejected the query) rather than
      // failing the whole NextUp row.
    }
  }

  if (extraItems.isEmpty) return nextUpItems;
  return [...extraItems, ...nextUpItems];
}

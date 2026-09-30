import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/models/playable_channel.dart';
import '../../../data/repositories/m3u_repository.dart';
import '../../../data/repositories/xtream_repository.dart';
import '../../../preference/user_preferences.dart';
import 'xtream_player_screen.dart';

/// 30.09, Sid: direct IPTV channel list, across every configured source -
/// Xtream Codes providers (filtered to the categories she picked in
/// XtreamCategoryPickerScreen) and plain M3U playlists alike ("j'ai fait
/// une m3u qui regroupe mes 3 listes... rajoute [le support]"). Both
/// collapse to the same PlayableChannel shape before they ever reach this
/// screen or the player, which never needs to know which kind of source a
/// given channel came from. Tapping a channel opens XtreamPlayerScreen
/// with the full filtered list, so zapping there cycles through exactly
/// what's shown here.
class XtreamChannelsScreen extends StatefulWidget {
  const XtreamChannelsScreen({super.key});

  @override
  State<XtreamChannelsScreen> createState() => _XtreamChannelsScreenState();
}

class _XtreamChannelsScreenState extends State<XtreamChannelsScreen> {
  final _prefs = GetIt.instance<UserPreferences>();
  final _xtreamRepo = GetIt.instance<XtreamRepository>();
  final _m3uRepo = GetIt.instance<M3uRepository>();
  List<PlayableChannel>? _channels;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _channels = null;
      _error = null;
    });

    final xtreamProviders = _prefs.getXtreamProviders();
    final m3uProviders = _prefs.getM3uProviders();
    if (xtreamProviders.isEmpty && m3uProviders.isEmpty) {
      setState(() => _error =
          'Aucun fournisseur configuré. Va dans Réglages > Intégrations > IPTV.');
      return;
    }

    final selectedByProvider = _prefs.getXtreamSelectedCategoryIds();
    final excludedByProvider = _prefs.getXtreamExcludedChannelIds();
    final channels = <PlayableChannel>[];

    for (final provider in xtreamProviders) {
      final selectedCategoryIds = selectedByProvider[provider.id] ?? const [];
      if (selectedCategoryIds.isEmpty) continue;
      final excludedChannelIds =
          excludedByProvider[provider.id]?.toSet() ?? const {};

      final categories = await _xtreamRepo.getLiveCategories(provider);
      final categoryNames = {
        for (final c in categories) c.id: c.name,
      };

      for (final categoryId in selectedCategoryIds) {
        final streams = await _xtreamRepo.getLiveStreams(
          provider,
          categoryId: categoryId,
        );
        for (final stream in streams) {
          if (excludedChannelIds.contains(stream.streamId.toString())) {
            continue;
          }
          channels.add(PlayableChannel(
            name: stream.name,
            iconUrl: stream.iconUrl,
            streamUrl: provider.streamUrl(stream.streamId),
            sourceName: provider.name,
            groupTitle: categoryNames[categoryId] ?? categoryId,
            fetchEpg: () async {
              final listings =
                  await _xtreamRepo.getShortEpg(provider, stream.streamId);
              return [
                for (final e in listings)
                  (title: e.title, start: e.start, end: e.end),
              ];
            },
          ));
        }
      }
    }

    for (final provider in m3uProviders) {
      final parsed = await _m3uRepo.fetchChannels(provider);
      channels.addAll(parsed);
    }

    if (!mounted) return;
    setState(() {
      _channels = channels;
      if (channels.isEmpty) {
        _error =
            'Aucune chaîne trouvée. Choisis des catégories pour tes fournisseurs Xtream, ou vérifie tes M3U.';
      }
    });
  }

  void _play(List<PlayableChannel> channels, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => XtreamPlayerScreen(
          channels: channels,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channels = _channels;
    final filtered = channels == null
        ? const <PlayableChannel>[]
        : channels
            .where((c) =>
                _filter.isEmpty ||
                c.name.toLowerCase().contains(_filter.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chaînes IPTV'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher une chaîne...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : channels == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return ListTile(
                      leading: entry.iconUrl != null
                          ? Image.network(
                              entry.iconUrl!,
                              width: 40,
                              height: 40,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.live_tv),
                            )
                          : const Icon(Icons.live_tv),
                      title: Text(entry.name),
                      subtitle: Text(
                        entry.groupTitle.isEmpty
                            ? entry.sourceName
                            : '${entry.sourceName} · ${entry.groupTitle}',
                      ),
                      onTap: () => _play(filtered, index),
                    );
                  },
                ),
    );
  }
}

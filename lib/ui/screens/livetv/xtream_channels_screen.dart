import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/xtream_models.dart';
import '../../../data/repositories/xtream_repository.dart';
import '../../../preference/user_preferences.dart';
import '../../navigation/destinations.dart';

/// 30.09, Sid: direct IPTV channel list, across all configured Xtream
/// providers, filtered to only the categories she picked in
/// XtreamCategoryPickerScreen. Playback reuses TrailerPlayerScreen's
/// existing media_kit pipeline (it already falls back to playing any raw
/// non-YouTube URL directly, see trailer_player_screen.dart) rather than
/// building a whole new player entry point - works, but its UI/controls are
/// built for a short trailer, not a 24/7 live channel (no channel zapping,
/// no EPG overlay) - a real purpose-built live UI is follow-up work, not
/// done tonight.
class XtreamChannelsScreen extends StatefulWidget {
  const XtreamChannelsScreen({super.key});

  @override
  State<XtreamChannelsScreen> createState() => _XtreamChannelsScreenState();
}

class _ChannelEntry {
  final XtreamProvider provider;
  final XtreamChannel channel;
  final String categoryName;

  const _ChannelEntry(this.provider, this.channel, this.categoryName);
}

class _XtreamChannelsScreenState extends State<XtreamChannelsScreen> {
  final _prefs = GetIt.instance<UserPreferences>();
  final _repo = GetIt.instance<XtreamRepository>();
  List<_ChannelEntry>? _entries;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _entries = null;
      _error = null;
    });

    final providers = _prefs.getXtreamProviders();
    if (providers.isEmpty) {
      setState(() => _error =
          'Aucun fournisseur configuré. Va dans Réglages > Intégrations > IPTV.');
      return;
    }

    final selectedByProvider = _prefs.getXtreamSelectedCategoryIds();
    final entries = <_ChannelEntry>[];

    for (final provider in providers) {
      final selectedCategoryIds = selectedByProvider[provider.id] ?? const [];
      if (selectedCategoryIds.isEmpty) continue;

      final categories = await _repo.getLiveCategories(provider);
      final categoryNames = {
        for (final c in categories) c.id: c.name,
      };

      for (final categoryId in selectedCategoryIds) {
        final channels = await _repo.getLiveStreams(
          provider,
          categoryId: categoryId,
        );
        for (final channel in channels) {
          entries.add(_ChannelEntry(
            provider,
            channel,
            categoryNames[categoryId] ?? categoryId,
          ));
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _entries = entries;
      if (entries.isEmpty) {
        _error =
            'Aucune chaîne dans les catégories choisies. Va choisir des catégories pour tes fournisseurs.';
      }
    });
  }

  void _play(_ChannelEntry entry) {
    final url = entry.provider.streamUrl(entry.channel.streamId);
    context.push(Destinations.trailer(url: url));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final filtered = entries == null
        ? const <_ChannelEntry>[]
        : entries
            .where((e) =>
                _filter.isEmpty ||
                e.channel.name.toLowerCase().contains(_filter.toLowerCase()))
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
          : entries == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return ListTile(
                      leading: entry.channel.iconUrl != null
                          ? Image.network(
                              entry.channel.iconUrl!,
                              width: 40,
                              height: 40,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.live_tv),
                            )
                          : const Icon(Icons.live_tv),
                      title: Text(entry.channel.name),
                      subtitle: Text('${entry.provider.name} · ${entry.categoryName}'),
                      onTap: () => _play(entry),
                    );
                  },
                ),
    );
  }
}

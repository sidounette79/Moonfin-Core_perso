import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/models/playable_channel.dart';
import '../../../data/services/epg_channel_matcher.dart';
import '../../../data/services/iptv_channel_loader.dart';
import '../../../preference/user_preferences.dart';
import 'epg/xtream_epg_screen.dart';
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
  final _loader = IptvChannelLoader();
  final _prefs = GetIt.instance<UserPreferences>();
  List<PlayableChannel>? _channels;
  String? _error;
  String _filter = '';
  bool _favoritesOnly = false;
  Set<String> _favorites = {};

  bool _isFavorite(PlayableChannel channel) =>
      _favorites.contains(EpgChannelMatcher.groupingKey(channel.name));

  Future<void> _toggleFavorite(PlayableChannel channel) async {
    final key = EpgChannelMatcher.groupingKey(channel.name);
    final nowFavorite = !_favorites.contains(key);
    await _prefs.setIptvChannelFavorite(key, nowFavorite);
    setState(() => _favorites = _prefs.getIptvFavoriteChannels());
  }

  @override
  void initState() {
    super.initState();
    _favorites = _prefs.getIptvFavoriteChannels();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _channels = null;
      _error = null;
    });

    if (!_loader.hasAnyProvider) {
      setState(() => _error =
          'Aucun fournisseur configuré. Va dans Réglages > Intégrations > IPTV.');
      return;
    }

    final channels = await _loader.load();

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
            .where((c) => !_favoritesOnly || _isFavorite(c))
            .toList()
          // Favorites first, stable otherwise (List.sort is stable in
          // Dart) so the rest keeps whatever order _loader.load() built.
          ..sort((a, b) {
            final favA = _isFavorite(a) ? 0 : 1;
            final favB = _isFavorite(b) ? 0 : 1;
            return favA.compareTo(favB);
          });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chaînes IPTV'),
        actions: [
          IconButton(
            icon: Icon(_favoritesOnly ? Icons.favorite : Icons.favorite_border),
            tooltip: 'Favoris uniquement',
            onPressed: () =>
                setState(() => _favoritesOnly = !_favoritesOnly),
          ),
          IconButton(
            icon: const Icon(Icons.grid_view),
            tooltip: 'Guide des programmes',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const XtreamEpgScreen()),
            ),
          ),
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
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ProviderBadge(sourceName: entry.sourceName),
                        ],
                      ),
                      subtitle: entry.groupTitle.isEmpty
                          ? null
                          : Text(entry.groupTitle),
                      trailing: IconButton(
                        icon: Icon(
                          _isFavorite(entry)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _isFavorite(entry) ? Colors.redAccent : null,
                        ),
                        onPressed: () => _toggleFavorite(entry),
                      ),
                      onTap: () => _play(filtered, index),
                    );
                  },
                ),
    );
  }
}

/// A small coloured pill naming which provider a channel came from - the
/// same colour every time for a given source name (hashed), so the same
/// provider reads as visually consistent down the whole list without
/// needing to remember an arbitrary legend.
class _ProviderBadge extends StatelessWidget {
  final String sourceName;

  const _ProviderBadge({required this.sourceName});

  static const _palette = [
    Color(0xFF2E7D8A),
    Color(0xFF6C4BD8),
    Color(0xFFC08A2E),
    Color(0xFF2E8B57),
    Color(0xFFC0497A),
    Color(0xFF3D5A80),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[sourceName.hashCode.abs() % _palette.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        sourceName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

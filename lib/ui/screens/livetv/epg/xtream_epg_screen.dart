import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../data/models/playable_channel.dart';
import '../../../../data/services/epg_channel_matcher.dart';
import '../../../../data/services/iptv_channel_loader.dart';
import '../../../../preference/user_preferences.dart';
import '../xtream_player_screen.dart';
import 'epg_genre.dart';
import 'widgets/epg_channel_cell.dart';
import 'widgets/epg_program_cell.dart';

/// 30.09, Sid: "on AURA UNE PAGE dans TV en direct similaire à clubtivi ?
/// Avec la grille ?" - a real multi-channel programme grid for Xtream/M3U
/// channels, reusing the same EpgChannelCell/EpgProgramCell presentation
/// widgets the Emby Live TV guide already uses (they're pure presentation,
/// no Emby model dependency) rather than forking that 3000+ line screen,
/// which is tied throughout to Emby's own paginated GuideProgram API - a
/// fundamentally different shape from PlayableChannel.fetchEpg's flat list.
///
/// Simpler than that screen on purpose for a first version: one shared
/// window (now-1h to now+5h) rather than multi-day paging, one shared
/// horizontal ScrollController across every row rather than per-cell focus
/// traversal. Good enough to actually see and use the EPG data the M3U
/// matching now produces; can grow toward the Emby guide's sophistication
/// later if it earns its keep.
class XtreamEpgScreen extends StatefulWidget {
  const XtreamEpgScreen({super.key});

  @override
  State<XtreamEpgScreen> createState() => _XtreamEpgScreenState();
}

class _XtreamEpgScreenState extends State<XtreamEpgScreen> {
  static const _railWidth = 160.0;
  static const _pixelsPerHour = 220.0;
  static const _windowBefore = Duration(hours: 1);
  static const _windowAfter = Duration(hours: 5);

  final _loader = IptvChannelLoader();
  final _prefs = GetIt.instance<UserPreferences>();
  late Set<String> _favorites = _prefs.getIptvFavoriteChannels();
  // The ruler is the one real drag surface; every row's own scrollview is
  // NeverScrollable and just mirrors the ruler's offset (see
  // _onRulerScroll) - dragging any one row directly isn't wired, the ruler
  // is the intended handle, same as most EPG grids.
  final _rulerController = ScrollController();
  final _rowsController = ScrollController();
  late final DateTime _windowStart;
  late final DateTime _windowEnd;

  List<PlayableChannel>? _channels;
  String? _error;
  final Map<int, List<EpgEntryData>> _programsByChannel = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _windowStart = now.subtract(_windowBefore);
    _windowEnd = now.add(_windowAfter);
    _load();
  }

  @override
  void dispose() {
    _rulerController.dispose();
    _rowsController.dispose();
    super.dispose();
  }

  bool _onRulerScroll(ScrollNotification notification) {
    if (_rowsController.hasClients) {
      _rowsController.jumpTo(
        notification.metrics.pixels.clamp(
          0.0,
          _rowsController.position.maxScrollExtent,
        ),
      );
    }
    return false;
  }

  Future<void> _load() async {
    setState(() {
      _channels = null;
      _error = null;
    });

    if (!_loader.hasAnyProvider) {
      setState(
        () => _error =
            'Aucun fournisseur configuré. Va dans Réglages > Intégrations > IPTV.',
      );
      return;
    }

    final channels = await _loader.load();
    if (!mounted) return;
    setState(() => _channels = channels);

    for (var i = 0; i < channels.length; i++) {
      final fetchEpg = channels[i].fetchEpg;
      if (fetchEpg == null) continue;
      unawaited(
        fetchEpg().then((entries) {
          if (!mounted) return;
          setState(() => _programsByChannel[i] = entries);
        }),
      );
    }
  }

  double _xFor(DateTime time) {
    final clamped = time.isBefore(_windowStart)
        ? _windowStart
        : (time.isAfter(_windowEnd) ? _windowEnd : time);
    final hoursFromStart =
        clamped.difference(_windowStart).inMinutes / 60.0;
    return hoursFromStart * _pixelsPerHour;
  }

  void _play(List<PlayableChannel> channels, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            XtreamPlayerScreen(channels: channels, initialIndex: index),
      ),
    );
  }

  Future<void> _toggleFavorite(PlayableChannel channel) async {
    final key = EpgChannelMatcher.groupingKey(channel.name);
    final nowFavorite = !_favorites.contains(key);
    await _prefs.setIptvChannelFavorite(key, nowFavorite);
    setState(() => _favorites = _prefs.getIptvFavoriteChannels());
  }

  Widget _timeRuler() {
    final hours = _windowEnd.difference(_windowStart).inHours;
    return SizedBox(
      height: 32,
      width: hours * _pixelsPerHour,
      child: Stack(
        children: [
          for (var h = 0; h <= hours; h++)
            Positioned(
              left: h * _pixelsPerHour,
              top: 0,
              bottom: 0,
              child: Container(
                width: 1,
                color: AppColorScheme.onSurface.withValues(alpha: 0.15),
              ),
            ),
          for (var h = 0; h < hours; h++)
            Positioned(
              left: h * _pixelsPerHour + 6,
              top: 6,
              child: Text(
                TimeOfDay.fromDateTime(
                  _windowStart.add(Duration(hours: h)),
                ).format(context),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          Positioned(
            left: _xFor(DateTime.now()),
            top: 0,
            bottom: 0,
            child: Container(width: 2, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  Widget _channelRow(List<PlayableChannel> channels, int index) {
    final channel = channels[index];
    final programs = _programsByChannel[index];
    final hours = _windowEnd.difference(_windowStart).inHours;

    return SizedBox(
      height: 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _railWidth,
            child: GestureDetector(
              onTap: () => _play(channels, index),
              onLongPress: () => _toggleFavorite(channel),
              child: EpgChannelCell(
                logoUrl: channel.iconUrl,
                name: channel.name,
                number: '${index + 1}',
                focused: false,
                apple: false,
                isFavorite: _favorites.contains(
                  EpgChannelMatcher.groupingKey(channel.name),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _rowsController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: hours * _pixelsPerHour,
                child: programs == null
                    ? EpgProgramCell(
                        title: '',
                        genre: const EpgGenre('', Colors.transparent),
                        isLive: false,
                        progress: 0,
                        hasTimer: false,
                        focused: false,
                        apple: false,
                        loading: true,
                      )
                    : Stack(
                        children: [
                          for (final p in programs)
                            if (p.end.isAfter(_windowStart) &&
                                p.start.isBefore(_windowEnd))
                              Positioned(
                                left: _xFor(p.start),
                                width:
                                    (_xFor(p.end) - _xFor(p.start)).clamp(
                                      4.0,
                                      double.infinity,
                                    ),
                                top: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  onTap: () => _play(channels, index),
                                  child: EpgProgramCell(
                                    title: p.title,
                                    genre: const EpgGenre(
                                      '',
                                      Colors.transparent,
                                    ),
                                    isLive: DateTime.now().isAfter(p.start) &&
                                        DateTime.now().isBefore(p.end),
                                    progress:
                                        DateTime.now().isAfter(p.start) &&
                                            DateTime.now().isBefore(p.end)
                                        ? DateTime.now()
                                                  .difference(p.start)
                                                  .inSeconds /
                                              p.end
                                                  .difference(p.start)
                                                  .inSeconds
                                                  .clamp(1, 1 << 30)
                                        : 0,
                                    hasTimer: false,
                                    focused: false,
                                    apple: false,
                                    startsBeforeWindow: p.start.isBefore(
                                      _windowStart,
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channels = _channels;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guide des programmes'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!)))
          : channels == null
          ? const Center(child: CircularProgressIndicator())
          : channels.isEmpty
          ? const Center(child: Text('Aucune chaîne trouvée.'))
          : Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: _railWidth),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onRulerScroll,
                        child: SingleChildScrollView(
                          controller: _rulerController,
                          scrollDirection: Axis.horizontal,
                          child: _timeRuler(),
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: channels.length,
                    itemBuilder: (context, index) =>
                        _channelRow(channels, index),
                  ),
                ),
              ],
            ),
    );
  }
}

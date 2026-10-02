import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/playable_channel.dart';
import '../../../data/services/epg_channel_matcher.dart';
import '../../../data/services/iptv_channel_loader.dart';
import '../../../data/services/iptv_player_service.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../widgets/local_search_field.dart';
import 'epg/epg_genre.dart';
import 'epg/widgets/epg_channel_cell.dart';
import 'epg/widgets/epg_program_cell.dart';
import 'xtream_player_screen.dart';

/// 01.10, Sid: "à l'ouverture de la page, qu'on ait la même UI que
/// clubtivi et pas juste la liste des chaines" - one screen now, modelled
/// on clubTivi's own channels_screen.dart (github.com/clubanderson/
/// clubTivi, Apache 2.0, see THIRD_PARTY_NOTICES.md): a filter sidebar on
/// the left, a persistent mini preview + now-playing panel up top, and the
/// programme grid filling the rest - instead of a flat ListView with the
/// grid buried behind a separate route (what this screen used to be, and
/// what XtreamEpgScreen used to be as its own screen; that screen is gone,
/// folded in here).
///
/// Adapted in spirit, not ported: clubTivi backs this with a Drift
/// database (many-to-many favourite lists, a dedicated failover-group
/// table, per-row synced ScrollControllers via manual Transform.translate
/// for its scale of guide). This keeps Moonfin's existing single-list
/// favourites (UserPreferences.getIptvFavoriteChannels) and its existing
/// mirrored-ScrollController EPG sync (good enough at the channel counts
/// Sid actually has configured) - only the single-screen layout and the
/// sidebar's filter-by-prefix idea are carried over.
class XtreamChannelsScreen extends StatefulWidget {
  const XtreamChannelsScreen({super.key});

  @override
  State<XtreamChannelsScreen> createState() => _XtreamChannelsScreenState();
}

class _XtreamChannelsScreenState extends State<XtreamChannelsScreen> {
  static const _railWidth = 200.0;
  static const _pixelsPerHour = 220.0;
  static const _windowBefore = Duration(hours: 1);
  static const _windowAfter = Duration(hours: 5);

  final _loader = IptvChannelLoader();
  final _prefs = GetIt.instance<UserPreferences>();
  final _service = GetIt.instance<IptvPlayerService>();

  List<PlayableChannel>? _channels;
  String? _error;
  String _filter = '';
  Set<String> _favorites = {};

  /// Which slice of the channel list the grid shows - a single string with
  /// a conventional prefix (clubTivi's own trick, see sidebar §5 of the
  /// upstream analysis) rather than an enum plus a parallel id field:
  /// 'All', 'Favorites', `provider:<sourceName>`, or `group:<groupTitle>`.
  String _selectedFilter = 'All';
  final Set<String> _expandedSections = {
    'favorites',
    'providers',
    'groups',
  };

  StreamSubscription<void>? _playerSub;
  final _rulerController = ScrollController();
  final _rowsController = ScrollController();
  final _verticalController = ScrollController();

  // 01.10, Sid: "Ca s'ouvre sur la ligne de recherche et je peux pas en
  // sortir avec la télécommande" - this whole screen shipped with no TV
  // D-pad wiring at all (grid/sidebar used plain GestureDetector/ListTile,
  // never tested on an actual TV). This is the minimum fix: a real TV
  // search field (LocalSearchField, same one library_browse_screen.dart
  // uses - a plain TextField captures the arrow keys itself for cursor
  // movement on TV, which is why DOWN never reached Flutter's focus
  // system) plus one escape target. The EPG grid itself staying
  // unreachable by remote is a separate, larger piece of work - not
  // attempted here.
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'iptvSearch');
  final _allChannelsTileFocusNode = FocusNode(debugLabel: 'iptvAllChannelsTile');
  late final DateTime _windowStart;
  late final DateTime _windowEnd;

  // 01.10, Sid: originally a TiviMate-style full show/hide staircase;
  // 02.10 switched the sidebar itself to clubTivi's own real behaviour
  // (shrinks to a 44px icon rail instead of disappearing - see
  // _buildSidebar's own note), but the grid's own focus model here is
  // unchanged: LEFT/RIGHT move between a channel's own programmes in time
  // (LEFT goes further into the past, for replay), UP/DOWN move to the
  // adjacent channel's programme at roughly the same time, BACK (not
  // LEFT) leaves the grid for the sidebar. One Focus node for the whole
  // grid rather than one per cell - hundreds of real FocusNodes for a
  // grid this size would be wasteful and the highlighted cell is drawn
  // from this logical position instead.
  bool _gridHasFocus = false;
  final _gridFocusNode = FocusNode(debugLabel: 'iptvGrid');
  int _focusedChannelIndex = 0;
  DateTime? _focusedProgramStart;

  /// Keyed by streamUrl (stable across re-filtering) rather than list
  /// index, and holding the Future itself (not just its resolved value) so
  /// a FutureBuilder rebuild reuses the same instance instead of flashing
  /// back to "waiting" every time the grid filter changes.
  final Map<String, Future<List<EpgEntryData>>> _epgFutures = {};

  /// Synchronous mirror of whatever _epgFutures has resolved so far -
  /// D-pad navigation needs to read a channel's programme list without
  /// waiting on a FutureBuilder rebuild cycle.
  final Map<String, List<EpgEntryData>> _resolvedPrograms = {};

  Future<List<EpgEntryData>> _epgForResolving(PlayableChannel channel) {
    final fetchEpg = channel.fetchEpg;
    if (fetchEpg == null) return Future.value(const []);
    return _epgFutures.putIfAbsent(channel.streamUrl, () async {
      final result = await fetchEpg();
      _resolvedPrograms[channel.streamUrl] = result;
      return result;
    });
  }

  /// Index of the programme covering (or, failing that, closest in start
  /// time to) `anchor` - used both to move LEFT/RIGHT within one channel's
  /// own programmes and, after an UP/DOWN hop, to re-anchor onto whichever
  /// programme sits at roughly the same time on the new channel.
  int _programIndexAt(List<EpgEntryData> programs, DateTime anchor) {
    for (var i = 0; i < programs.length; i++) {
      if (!anchor.isBefore(programs[i].start) && anchor.isBefore(programs[i].end)) {
        return i;
      }
    }
    var best = 0;
    var bestDiff = programs[0].start.difference(anchor).abs();
    for (var i = 1; i < programs.length; i++) {
      final diff = programs[i].start.difference(anchor).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  /// Scrolls the time axis (ruler + every row, mirrored) just enough to
  /// bring [start, end) into view - same "ensure visible" idea as
  /// Scrollable.ensureVisible, hand-rolled because the axis is driven by
  /// two mirrored horizontal ScrollControllers, not Flutter's own
  /// Scrollable machinery.
  void _ensureProgramVisible(DateTime start, DateTime end) {
    if (!_rulerController.hasClients) return;
    final left = _xFor(start);
    final right = _xFor(end);
    final viewport = _rulerController.position.viewportDimension;
    final current = _rulerController.offset;
    double? target;
    if (left < current) {
      target = left;
    } else if (right > current + viewport) {
      target = right - viewport;
    }
    if (target == null) return;
    final clamped = target.clamp(0.0, _rulerController.position.maxScrollExtent);
    _rulerController.jumpTo(clamped);
    if (_rowsController.hasClients) {
      _rowsController.jumpTo(
        clamped.clamp(0.0, _rowsController.position.maxScrollExtent),
      );
    }
  }

  /// Same idea as [_ensureProgramVisible], vertically, for the focused
  /// channel row - rows are a fixed 64px tall (see _channelRow).
  void _ensureChannelVisible(int index) {
    if (!_verticalController.hasClients) return;
    const rowHeight = 64.0;
    final top = index * rowHeight;
    final bottom = top + rowHeight;
    final viewport = _verticalController.position.viewportDimension;
    final current = _verticalController.offset;
    double? target;
    if (top < current) {
      target = top;
    } else if (bottom > current + viewport) {
      target = bottom - viewport;
    }
    if (target == null) return;
    _verticalController.jumpTo(
      target.clamp(0.0, _verticalController.position.maxScrollExtent),
    );
  }

  bool _isFavorite(PlayableChannel c) =>
      _favorites.contains(EpgChannelMatcher.groupingKey(c.name));

  Future<void> _toggleFavorite(PlayableChannel channel) async {
    final key = EpgChannelMatcher.groupingKey(channel.name);
    final nowFavorite = !_favorites.contains(key);
    await _prefs.setIptvChannelFavorite(key, nowFavorite);
    setState(() => _favorites = _prefs.getIptvFavoriteChannels());
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _windowStart = now.subtract(_windowBefore);
    _windowEnd = now.add(_windowAfter);
    _favorites = _prefs.getIptvFavoriteChannels();
    _playerSub = _service.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _rulerController.dispose();
    _rowsController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _allChannelsTileFocusNode.dispose();
    // Reused as sidebar index 0 inside _sidebarFocusNodes (see
    // _nextSidebarFocusNode's `reuse` param) - skip it here, already
    // disposed just above, or this screen could close before
    // _buildSidebar ever ran once (error/loading state) and it wouldn't
    // be in this list at all.
    for (final node in _sidebarFocusNodes) {
      if (identical(node, _allChannelsTileFocusNode)) continue;
      node.dispose();
    }
    _gridFocusNode.dispose();
    _verticalController.dispose();
    // Actually leaving the IPTV section (not just pushing the fullscreen
    // route on top - that doesn't dispose this screen, see
    // IptvPlayerService's own lifecycle note).
    _service.stop();
    super.dispose();
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

  List<PlayableChannel> get _filtered {
    final all = _channels ?? const <PlayableChannel>[];
    Iterable<PlayableChannel> result = all;
    if (_selectedFilter == 'Favorites') {
      result = result.where(_isFavorite);
    } else if (_selectedFilter.startsWith('provider:')) {
      final name = _selectedFilter.substring('provider:'.length);
      result = result.where((c) => c.sourceName == name);
    } else if (_selectedFilter.startsWith('group:')) {
      final name = _selectedFilter.substring('group:'.length);
      result = result.where((c) => c.groupTitle == name);
    }
    if (_filter.isNotEmpty) {
      result = result.where(
        (c) => c.name.toLowerCase().contains(_filter.toLowerCase()),
      );
    }
    final list = result.toList()
      ..sort((a, b) {
        final favA = _isFavorite(a) ? 0 : 1;
        final favB = _isFavorite(b) ? 0 : 1;
        return favA.compareTo(favB);
      });
    return list;
  }

  void _openInPreview(List<PlayableChannel> list, int index) {
    unawaited(_service.openChannels(list, index));
  }

  void _openFullscreen(List<PlayableChannel> list, int index) {
    _openInPreview(list, index);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            XtreamPlayerScreen(channels: list, initialIndex: index),
      ),
    );
  }

  void _openFullscreenCurrent() {
    if (_service.channels.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => XtreamPlayerScreen(
          channels: _service.channels,
          initialIndex: _service.currentIndex,
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  EpgEntryData? get _currentProgram {
    final epg = _service.epg;
    if (epg.isEmpty) return null;
    final now = DateTime.now();
    for (final e in epg) {
      if (now.isAfter(e.start) && now.isBefore(e.end)) return e;
    }
    return null;
  }

  // ---- Sidebar -------------------------------------------------------

  /// 02.10, Sid: "je peux descendre dedans mais pas remonter" + "pas de
  /// visuel sur quelle ligne" - Flutter's own default directional focus
  /// traversal was behind both: relying on it for UP/DOWN inside a
  /// ListView with collapsible sections turned out unreliable once the
  /// sidebar's content changed shape, and a plain Focus-wrapped ListTile
  /// has no built-in "I currently hold focus" visual of its own. Explicit
  /// handling here mirrors what the grid already does (_onGridKeyEvent) -
  /// one flat, build-order list of nodes, and the key handler moves
  /// between adjacent indices itself instead of trusting the platform to
  /// get there. Rebuilt fresh (not grown-and-reused) at the start of every
  /// _buildSidebar() call since which tiles exist (expanded sections,
  /// filtered providers/groups) changes between builds.
  final List<FocusNode> _sidebarFocusNodes = [];
  int _sidebarBuildCounter = 0;

  FocusNode _nextSidebarFocusNode({FocusNode? reuse}) {
    final index = _sidebarBuildCounter++;
    final node = reuse ?? FocusNode(debugLabel: 'iptvSidebar$index');
    if (_sidebarFocusNodes.length <= index) {
      _sidebarFocusNodes.add(node);
    } else {
      _sidebarFocusNodes[index] = node;
    }
    return node;
  }

  /// RIGHT from any sidebar tile enters the grid, landing on its first row
  /// - same "staircase" idea TiviMate uses, see this screen's own header
  /// comment. UP/DOWN move between sidebar tiles explicitly (see the
  /// _sidebarFocusNodes note above) rather than through Flutter's default
  /// traversal.
  KeyEventResult _onSidebarTileKeyEvent(FocusNode node, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key.isRightKey) {
      final list = _filtered;
      if (list.isEmpty) return KeyEventResult.ignored;
      setState(() {
        _gridHasFocus = true;
        _sidebarExpanded = false;
        _focusedChannelIndex = _focusedChannelIndex.clamp(0, list.length - 1);
        _focusedProgramStart ??= DateTime.now();
      });
      _gridFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (key.isUpKey || key.isDownKey) {
      final index = _sidebarFocusNodes.indexOf(node);
      if (index < 0) return KeyEventResult.ignored;
      final nextIndex = key.isUpKey ? index - 1 : index + 1;
      if (nextIndex < 0 || nextIndex >= _sidebarFocusNodes.length) {
        return KeyEventResult.handled;
      }
      _sidebarFocusNodes[nextIndex].requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Focus ring + collapsed/expanded body shared by every sidebar row
  /// (filter tiles and section headers alike) - clubTivi's own
  /// _sidebarIcon/_buildSidebarNavItem split these in two; folded into one
  /// helper here since both this screen's tile kinds need the exact same
  /// focus-node wiring either way.
  Widget _sidebarRow({
    required FocusNode node,
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    Widget? expandedTrailing,
  }) {
    return Focus(
      focusNode: node,
      onKeyEvent: _onSidebarTileKeyEvent,
      child: ListenableBuilder(
        listenable: node,
        builder: (context, _) {
          final body = Container(
            height: 36,
            decoration: BoxDecoration(
              color: active ? Colors.white.withValues(alpha: 0.08) : null,
              border: node.hasFocus
                  ? Border.all(color: _clubTiviFocusBorder, width: 1.5)
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: _sidebarExpanded
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: Colors.white70),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        ?expandedTrailing,
                      ],
                    ),
                  )
                : Icon(
                    icon,
                    size: 18,
                    color: active ? Colors.white : Colors.white38,
                  ),
          );
          return Tooltip(
            message: _sidebarExpanded ? '' : label,
            preferBelow: false,
            child: InkWell(onTap: onTap, child: body),
          );
        },
      ),
    );
  }

  Widget _sidebarTile(
    String label,
    String filterValue, {
    IconData? icon,
    int? count,
    FocusNode? focusNode,
  }) {
    final selected = _selectedFilter == filterValue;
    final node = _nextSidebarFocusNode(reuse: focusNode);
    return _sidebarRow(
      node: node,
      icon: icon ?? Icons.circle_outlined,
      label: label,
      active: selected,
      onTap: () => setState(() => _selectedFilter = filterValue),
      expandedTrailing: count != null
          ? Text(
              '$count',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            )
          : null,
    );
  }

  /// [itemCount] decides whether the section exists at all (e.g. no
  /// providers configured); [buildChildren] is only called when the
  /// section will actually mount its children.
  ///
  /// 02.10, bug trouvé en audit: cette méthode prenait avant une
  /// `List<Widget> children` déjà construite par l'appelant - mais un
  /// literal `[for (...) _sidebarTile(...)]` est évalué par Dart avant
  /// même d'être passé ici, donc chaque tuile consommait un FocusNode via
  /// `_nextSidebarFocusNode()` MÊME quand la section était repliée (ou le
  /// panneau entier réduit en rail). Ces noeuds restaient enregistrés dans
  /// `_sidebarFocusNodes` sans jamais être montés dans l'arbre, et
  /// `_onSidebarTileKeyEvent` pouvait appeler `.requestFocus()` sur l'un
  /// d'eux - sans effet visible, UP/DOWN semblait ne rien faire depuis
  /// l'en-tête d'une section repliée. Un callback appelé seulement quand
  /// les enfants vont réellement être montés ferme cet écart.
  Widget _sidebarSection(
    String key,
    String title,
    int itemCount,
    List<Widget> Function() buildChildren,
  ) {
    if (itemCount == 0) return const SizedBox.shrink();
    final expanded = _expandedSections.contains(key);
    final node = _nextSidebarFocusNode();
    final showChildren = expanded && _sidebarExpanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sidebarRow(
          node: node,
          icon: Icons.folder_rounded,
          label: title,
          active: false,
          onTap: () => setState(() {
            if (expanded) {
              _expandedSections.remove(key);
            } else {
              _expandedSections.add(key);
              _sidebarExpanded = true;
            }
          }),
          expandedTrailing: Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: Colors.white38,
          ),
        ),
        if (showChildren) ...buildChildren(),
      ],
    );
  }

  // 02.10, Sid: "reprendre le visuel clubtivi à l'identique" - confirmed
  // against their real source (channels_screen.dart _buildSidebar, not
  // guessed): the sidebar doesn't hide, it SHRINKS to a 44px icon rail
  // (220px expanded), width-animated, toggled by a chevron button - not
  // tied to D-pad focus location the way the earlier TiviMate-inspired
  // staircase was. Colors are their exact literal values
  // (#111127 sidebar bg), a deliberate one-screen exception to Moonfin's
  // own dynamic AppColorScheme since an "identical copy" was the ask.
  static const _clubTiviSidebarBg = Color(0xFF111127);
  // 02.10: their own _sidebarIcon helper uses the lighter Colors.purpleAccent
  // for JUST that one collapsed-icon widget, but every other focus ring in
  // their source (channel rows, programme cells) uses the theme's real
  // accent (ClubTiviTheme._accent) - using that one consistently here so
  // the sidebar's focus ring matches the rest of this screen, not the
  // one inconsistent spot in their own code.
  static const _clubTiviFocusBorder = Color(0xFF6C5CE7);
  static const _clubTiviSidebarExpandedWidth = 220.0;
  static const _clubTiviSidebarCollapsedWidth = 44.0;
  static const _clubTiviCellStyle = EpgCellStyleOverride(
    restingBackground: Color(0xFF16213E),
    focusedBackground: Color(0x296C5CE7), // 0xFF6C5CE7 at ~16% alpha
    focusBorderColor: Color(0xFF6C5CE7),
    nameColor: Colors.white,
    logoFallbackBackground: Color(0xFF16213E),
  );

  bool _sidebarExpanded = true;

  Widget _buildSidebar() {
    _sidebarBuildCounter = 0;
    final channels = _channels ?? const <PlayableChannel>[];
    final providers = channels.map((c) => c.sourceName).toSet().toList()
      ..sort();
    final groups =
        channels
            .map((c) => c.groupTitle)
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _sidebarExpanded
          ? _clubTiviSidebarExpandedWidth
          : _clubTiviSidebarCollapsedWidth,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(color: _clubTiviSidebarBg),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: _sidebarExpanded
                  ? Alignment.centerRight
                  : Alignment.center,
              child: Icon(
                _sidebarExpanded
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: Colors.white38,
                size: 20,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _sidebarTile(
                  'Toutes les chaînes',
                  'All',
                  icon: Icons.apps,
                  count: channels.length,
                  focusNode: _allChannelsTileFocusNode,
                ),
                _sidebarSection(
                  'favorites',
                  'Favoris',
                  1,
                  () => [
                    _sidebarTile(
                      'Favoris',
                      'Favorites',
                      icon: Icons.favorite,
                      count: _favorites.length,
                    ),
                  ],
                ),
                _sidebarSection(
                  'providers',
                  'Fournisseurs',
                  providers.length,
                  () => [
                    for (final p in providers)
                      _sidebarTile(p, 'provider:$p', icon: Icons.dns_outlined),
                  ],
                ),
                _sidebarSection(
                  'groups',
                  'Groupes (${groups.length})',
                  groups.length,
                  () => [
                    for (final g in groups)
                      _sidebarTile(g, 'group:$g', icon: Icons.folder_outlined),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Preview row -----------------------------------------------------

  Widget _buildPreviewRow() {
    final current = _service.current;
    final controller = _service.controller;
    final program = _currentProgram;

    return SizedBox(
      height: 200,
      child: Container(
        color: AppColorScheme.surface,
        child: Row(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: controller == null
                    ? const Center(
                        child: Icon(
                          Icons.live_tv,
                          color: Colors.white24,
                          size: 40,
                        ),
                      )
                    : GestureDetector(
                        onTap: _openFullscreenCurrent,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Video(controller: controller, controls: NoVideoControls),
                            if (_service.loading || _service.buffering)
                              const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: current == null
                    ? Text(
                        'Sélectionne une chaîne dans la grille',
                        style: TextStyle(
                          color: AppColorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  current.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _ProviderBadge(
                                sourceName:
                                    _service.activeSource?.sourceName ??
                                    current.sourceName,
                              ),
                            ],
                          ),
                          if (_service.error != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _service.error!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                              ),
                            ),
                          ] else if (program != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${_formatTime(program.start)} - ${_formatTime(program.end)}  ${program.title}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColorScheme.onSurface.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _isFavorite(current)
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: _isFavorite(current)
                                      ? Colors.redAccent
                                      : null,
                                ),
                                onPressed: () => _toggleFavorite(current),
                              ),
                              IconButton(
                                icon: const Icon(Icons.fullscreen),
                                tooltip: 'Plein écran',
                                onPressed: _openFullscreenCurrent,
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- EPG grid ----------------------------------------------------

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

  double _xFor(DateTime time) {
    final clamped = time.isBefore(_windowStart)
        ? _windowStart
        : (time.isAfter(_windowEnd) ? _windowEnd : time);
    final hoursFromStart = clamped.difference(_windowStart).inMinutes / 60.0;
    return hoursFromStart * _pixelsPerHour;
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

  /// Cellule par cellule, pas ligne par ligne: LEFT/RIGHT se déplacent dans
  /// le temps sur LA MÊME chaîne (LEFT = programme précédent, donc vers le
  /// passé - utile pour les quelques cas de replay), UP/DOWN sautent à la
  /// chaîne voisine en se recalant sur le programme le plus proche dans le
  /// temps (voir _programIndexAt). RETOUR (pas LEFT) sort de la grille vers
  /// la sidebar - LEFT est maintenant pris par la navigation temporelle.
  /// SELECT ouvre le plein écran, comme un tap souris.
  KeyEventResult _onGridKeyEvent(FocusNode node, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final list = _filtered;
    if (list.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key.isBackKey) {
      setState(() {
        _gridHasFocus = false;
        _sidebarExpanded = true;
      });
      _allChannelsTileFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    final channelIndex = _focusedChannelIndex.clamp(0, list.length - 1);
    final channel = list[channelIndex];
    final anchor = _focusedProgramStart ?? DateTime.now();

    if (key.isLeftKey || key.isRightKey) {
      final programs = _resolvedPrograms[channel.streamUrl];
      if (programs == null || programs.isEmpty) return KeyEventResult.handled;
      final currentIndex = _programIndexAt(programs, anchor);
      final newIndex = key.isLeftKey ? currentIndex - 1 : currentIndex + 1;
      if (newIndex < 0 || newIndex >= programs.length) {
        return KeyEventResult.handled;
      }
      setState(() {
        _focusedChannelIndex = channelIndex;
        _focusedProgramStart = programs[newIndex].start;
      });
      _ensureProgramVisible(programs[newIndex].start, programs[newIndex].end);
      return KeyEventResult.handled;
    }

    if (key.isUpKey || key.isDownKey) {
      final newChannelIndex = key.isUpKey ? channelIndex - 1 : channelIndex + 1;
      if (newChannelIndex < 0 || newChannelIndex >= list.length) {
        return KeyEventResult.handled;
      }
      final newPrograms = _resolvedPrograms[list[newChannelIndex].streamUrl];
      var newAnchor = anchor;
      if (newPrograms != null && newPrograms.isNotEmpty) {
        newAnchor = newPrograms[_programIndexAt(newPrograms, anchor)].start;
      }
      setState(() {
        _focusedChannelIndex = newChannelIndex;
        _focusedProgramStart = newAnchor;
      });
      _ensureChannelVisible(newChannelIndex);
      return KeyEventResult.handled;
    }

    if (key.isSelectKey) {
      _openFullscreen(list, channelIndex);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _channelRow(List<PlayableChannel> list, int index) {
    final channel = list[index];
    final hours = _windowEnd.difference(_windowStart).inHours;
    final isCurrent = _service.current?.streamUrl == channel.streamUrl;
    final isFocusedRow = _gridHasFocus && _focusedChannelIndex == index;

    return SizedBox(
      height: 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _railWidth,
            child: GestureDetector(
              onTap: () => _openFullscreen(list, index),
              onLongPress: () => _toggleFavorite(channel),
              child: EpgChannelCell(
                logoUrl: channel.iconUrl,
                name: channel.name,
                number: '${index + 1}',
                focused: isFocusedRow,
                playing: isCurrent,
                apple: false,
                isFavorite: _isFavorite(channel),
                styleOverride: _clubTiviCellStyle,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<EpgEntryData>>(
              future: _epgForResolving(channel),
              builder: (context, snapshot) {
                final programs =
                    snapshot.data ?? _resolvedPrograms[channel.streamUrl];
                EpgEntryData? focusedProgram;
                if (isFocusedRow && programs != null && programs.isNotEmpty) {
                  final idx = _programIndexAt(
                    programs,
                    _focusedProgramStart ?? DateTime.now(),
                  );
                  focusedProgram = programs[idx];
                }
                return SingleChildScrollView(
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
                            styleOverride: _clubTiviCellStyle,
                          )
                        : Stack(
                            children: [
                              for (final p in programs)
                                if (p.end.isAfter(_windowStart) &&
                                    p.start.isBefore(_windowEnd))
                                  Positioned(
                                    left: _xFor(p.start),
                                    width: (_xFor(p.end) - _xFor(p.start))
                                        .clamp(4.0, double.infinity),
                                    top: 0,
                                    bottom: 0,
                                    child: GestureDetector(
                                      onTap: () => _openFullscreen(list, index),
                                      child: EpgProgramCell(
                                        title: p.title,
                                        genre: const EpgGenre(
                                          '',
                                          Colors.transparent,
                                        ),
                                        isLive:
                                            DateTime.now().isAfter(p.start) &&
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
                                        focused: identical(p, focusedProgram),
                                        apple: false,
                                        startsBeforeWindow: p.start.isBefore(
                                          _windowStart,
                                        ),
                                        styleOverride: _clubTiviCellStyle,
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<PlayableChannel> list) {
    if (list.isEmpty) {
      return const Center(child: Text('Aucune chaîne dans cette catégorie.'));
    }
    return Column(
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
          child: Focus(
            focusNode: _gridFocusNode,
            onKeyEvent: _onGridKeyEvent,
            child: ListView.builder(
              controller: _verticalController,
              itemCount: list.length,
              itemBuilder: (context, index) => _channelRow(list, index),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final channels = _channels;

    // 01.10, Sid: "si je suis dans la grille et que je fais retour, je
    // reviens sur l'écran d'accueil de Moon" - the physical BACK button on
    // Android TV doesn't reach _onGridKeyEvent's own isBackKey handling at
    // all; it pops the route directly (Android's predictive-back/
    // onBackPressed path, not a KeyEvent Focus.onKeyEvent ever sees). Only
    // intercept the pop while focus is in the grid - once it's back on the
    // sidebar, BACK should behave normally and leave this whole screen.
    return PopScope(
      canPop: !_gridHasFocus,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          _gridHasFocus = false;
          _sidebarExpanded = true;
        });
        _allChannelsTileFocusNode.requestFocus();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF1A1A2E), // clubTivi's own scaffold bg
      appBar: AppBar(
        title: const Text('TV en direct'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: LocalSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (v) => setState(() => _filter = v),
              onTvKeyEvent: (node, event) {
                if (event.isActionable && event.logicalKey.isDownKey) {
                  _allChannelsTileFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
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
          : Column(
              children: [
                _buildPreviewRow(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 02.10: clubTivi's own sidebar never disappears, it
                      // just shrinks to the 44px icon rail (see
                      // _buildSidebar's own note) - always in the Row now,
                      // _sidebarExpanded (auto-toggled alongside
                      // _gridHasFocus below) does the staircase effect via
                      // its width animation instead of a full show/hide.
                      _buildSidebar(),
                      Expanded(child: _buildGrid(_filtered)),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

/// A small coloured pill naming which provider a channel came from - the
/// same colour every time for a given source name (hashed), so the same
/// provider reads as visually consistent without needing to remember an
/// arbitrary legend.
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

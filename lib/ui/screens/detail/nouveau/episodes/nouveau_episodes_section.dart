import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/util/season_queue_context.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../../data/viewmodels/item_detail_view_model.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../preference/preference_constants.dart';
import '../../../../../preference/user_preferences.dart';
import '../../../../../util/focus/dpad_keys.dart';
import '../../../../../util/platform_detection.dart';
import '../../../../navigation/destinations.dart';
import '../../../../widgets/focus/context_menu_sheet.dart';
import '../../../../widgets/focus/hub_focus_memory.dart';
import '../../../../widgets/offline_aware_image.dart';
import '../../../../widgets/seerr/seerr_image_urls.dart';
import '../../../../widgets/seerr/seerr_item_status.dart';
import '../../item_detail_screen.dart';
import '../shared/nouveau_spacing.dart';
import 'nouveau_season_selector.dart';

/// 30.10, Sid ("oui comme sur la maquette") - replaced the old horizontal,
/// continuous-scroll-across-all-seasons rail (LockedFocusRow) with a real
/// grid of the SELECTED season's episodes only, matching the mockup. A
/// season pill now filters which episodes show, rather than scrolling to
/// them - this drops the old scroll-position-driven season-sync machinery
/// entirely (mobile scroll sync, programmatic-scroll season detection),
/// since there's no more continuous scroll to sync against.
class NouveauEpisodesSection extends StatefulWidget {
  final ItemDetailViewModel viewModel;
  final GlobalKey<DetailActionButtonsState> actionButtonsKey;
  final UserPreferences prefs;
  final ValueChanged<AggregatedItem>? onBackdropItemFocused;
  final bool Function()? onNavigateUp;
  final bool Function()? onNavigateDown;

  /// 30.10, Sid (maquette "cliquer un épisode dans la grille, ça remonte
  /// dans la miniature du haut") - fires whenever the focused (TV D-pad) or
  /// selected (mobile tap) episode changes, so the preview card above the
  /// action buttons can show whichever episode is currently highlighted.
  /// 30.10 again ("ça lance l'épisode au lieu de faire venir dans la
  /// vignette") - a tap used to play directly; now it just selects, same
  /// as D-pad focus landing on a tile. Play only ever happens from the
  /// preview card itself (its thumbnail or Lire), never straight from
  /// this grid on either platform.
  final ValueChanged<AggregatedItem>? onEpisodeFocused;

  const NouveauEpisodesSection({
    super.key,
    required this.viewModel,
    required this.actionButtonsKey,
    required this.prefs,
    this.onBackdropItemFocused,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onEpisodeFocused,
  });

  @override
  State<NouveauEpisodesSection> createState() =>
      NouveauEpisodesSectionState();
}

class NouveauEpisodesSectionState extends State<NouveauEpisodesSection> {
  static int _episodeHubSession = 0;

  final GlobalKey<NouveauSeasonSelectorState> _seasonSelectorKey =
      GlobalKey<NouveauSeasonSelectorState>();

  final GlobalKey _artworkRailAnchorKey = GlobalKey();

  final Map<String, FocusNode> _episodeFocusNodes = {};

  int? _selectedSeasonNumber;
  int? _lastFocusedIndexInSeason;

  String? _lastPublishedBackdropKey;

  bool _initialBackdropSyncScheduled = false;
  bool _initialBackdropSyncComplete = false;
  bool _episodesInitialLoadComplete = false;

  late String _episodeHubKey;

  ItemDetailViewModel get _vm => widget.viewModel;

  GlobalKey get artworkRailAnchorKey => _artworkRailAnchorKey;

  bool get _isSeries => _vm.item?.type == 'Series';

  bool get _isSeason => _vm.item?.type == 'Season';

  bool get _navbarIsLeft =>
      widget.prefs.get(UserPreferences.navbarPosition) == NavbarPosition.left;

  bool _isCompactMobile(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return !PlatformDetection.isTV && size.shortestSide < 600;
  }

  List<AggregatedItem> get _sourceEpisodes {
    if (_isSeason) {
      return _vm.episodes;
    }

    return _vm.seriesEpisodes;
  }

  List<AggregatedItem> get _sortedEpisodes {
    return [..._sourceEpisodes]..sort((a, b) {
      final seasonCompare = (a.parentIndexNumber ?? 0).compareTo(
        b.parentIndexNumber ?? 0,
      );

      if (seasonCompare != 0) {
        return seasonCompare;
      }

      return (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0);
    });
  }

  @override
  void initState() {
    super.initState();

    _episodeHubKey = _createEpisodeHubKey();

    _beginEpisodesLoad();
  }

  @override
  void didUpdateWidget(covariant NouveauEpisodesSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (identical(oldWidget.viewModel, widget.viewModel)) {
      return;
    }

    _selectedSeasonNumber = null;
    _lastFocusedIndexInSeason = null;

    _lastPublishedBackdropKey = null;
    _initialBackdropSyncScheduled = false;
    _initialBackdropSyncComplete = false;

    _episodeHubKey = _createEpisodeHubKey();

    _disposeEpisodeFocusNodes();

    _episodesInitialLoadComplete = false;

    _beginEpisodesLoad();
  }

  @override
  void dispose() {
    _disposeEpisodeFocusNodes();

    super.dispose();
  }

  void _disposeEpisodeFocusNodes() {
    for (final node in _episodeFocusNodes.values) {
      node.dispose();
    }

    _episodeFocusNodes.clear();
  }

  void _beginEpisodesLoad() {
    final viewModel = _vm;

    if (_isSeason) {
      _episodesInitialLoadComplete = true;
      return;
    }

    if (!_isSeries) {
      _episodesInitialLoadComplete = true;
      return;
    }

    if (viewModel.seriesEpisodes.isNotEmpty) {
      _episodesInitialLoadComplete = true;
      return;
    }

    unawaited(
      viewModel.loadAllSeriesEpisodes().whenComplete(() {
        if (!mounted || !identical(_vm, viewModel)) {
          return;
        }

        setState(() {
          _episodesInitialLoadComplete = true;
        });
      }),
    );
  }

  String _createEpisodeHubKey() {
    final session = _episodeHubSession++;

    return 'nouveau-episodes-${_vm.item?.id}-$session';
  }

  FocusNode _episodeFocusNode(AggregatedItem episode) {
    return _episodeFocusNodes.putIfAbsent(episode.id, () {
      final node = FocusNode(debugLabel: 'episode:${episode.id}');

      node.addListener(() => _handleEpisodeFocusChange(episode, node));

      return node;
    });
  }

  void _pruneEpisodeFocusNodes(List<AggregatedItem> seasonEpisodes) {
    final ids = seasonEpisodes.map((episode) => episode.id).toSet();

    final stale = _episodeFocusNodes.keys
        .where((id) => !ids.contains(id))
        .toList(growable: false);

    for (final id in stale) {
      _episodeFocusNodes.remove(id)?.dispose();
    }
  }

  void _handleEpisodeFocusChange(AggregatedItem episode, FocusNode node) {
    if (!node.hasFocus || !mounted) {
      return;
    }

    widget.onEpisodeFocused?.call(episode);

    final seasonEpisodes = _episodesForSelectedSeason(_sortedEpisodes);
    final index = seasonEpisodes.indexWhere((e) => e.id == episode.id);

    if (index >= 0) {
      _lastFocusedIndexInSeason = index;

      HubFocusMemory.set(_episodeHubKey, index);
    }
  }

  bool get canFocusTop {
    if (!mounted) {
      return false;
    }

    return _episodesForSelectedSeason(_sortedEpisodes).isNotEmpty;
  }

  bool focusTop() {
    if (!mounted) {
      return false;
    }

    final seasonEpisodes = _episodesForSelectedSeason(_sortedEpisodes);

    if (seasonEpisodes.isEmpty) {
      return false;
    }

    if (_isSeries) {
      final selector = _seasonSelectorKey.currentState;

      if (selector != null &&
          selector.mounted &&
          selector.canFocusSelectedSeason) {
        final seasonNumbers = _seasonNumbersFor(_sortedEpisodes);

        selector.requestFocusAtSeason(_effectiveSelectedSeason(seasonNumbers));

        return true;
      }
    }

    return _focusEpisodeAt(seasonEpisodes, _rememberedIndex(seasonEpisodes));
  }

  bool focusBottom() {
    final seasonEpisodes = _episodesForSelectedSeason(_sortedEpisodes);

    if (seasonEpisodes.isEmpty) {
      return false;
    }

    return _focusEpisodeAt(seasonEpisodes, _rememberedIndex(seasonEpisodes));
  }

  int _rememberedIndex(List<AggregatedItem> seasonEpisodes) {
    final remembered =
        _lastFocusedIndexInSeason ?? HubFocusMemory.peek(_episodeHubKey);

    return (remembered ?? 0).clamp(0, seasonEpisodes.length - 1);
  }

  bool _focusEpisodeAt(List<AggregatedItem> seasonEpisodes, int index) {
    if (index < 0 || index >= seasonEpisodes.length) {
      return false;
    }

    final node = _episodeFocusNode(seasonEpisodes[index]);

    if (!node.canRequestFocus) {
      return false;
    }

    node.requestFocus();

    return true;
  }

  bool _handleSeasonNavigateUp() {
    return widget.onNavigateUp?.call() ?? false;
  }

  bool _handleSeasonNavigateDown(List<AggregatedItem> seasonEpisodes) {
    if (seasonEpisodes.isEmpty) {
      return true;
    }

    return _focusEpisodeAt(seasonEpisodes, _rememberedIndex(seasonEpisodes));
  }

  void _openEpisodeDetails(BuildContext context, AggregatedItem episode) {
    context.push(
      Destinations.item(
        episode.id,
        serverId: episode.serverId,
        seasonContext: seasonContextParam(
          contextSeasonId: _isSeason ? _vm.item?.id : null,
          episodeSeasonId: episode.seasonId,
        ),
      ),
    );
  }

  List<int> _seasonNumbersFor(List<AggregatedItem> episodes) {
    return episodes
        .map((episode) => episode.parentIndexNumber)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
  }

  int _effectiveSelectedSeason(List<int> seasonNumbers) {
    final selected = _selectedSeasonNumber;

    if (selected != null && seasonNumbers.contains(selected)) {
      return selected;
    }

    return seasonNumbers.first;
  }

  List<AggregatedItem> _episodesForSelectedSeason(
    List<AggregatedItem> episodes,
  ) {
    if (!_isSeries) {
      return episodes;
    }

    final seasonNumbers = _seasonNumbersFor(episodes);

    if (seasonNumbers.isEmpty) {
      return episodes;
    }

    final season = _effectiveSelectedSeason(seasonNumbers);

    return episodes
        .where((episode) => episode.parentIndexNumber == season)
        .toList(growable: false);
  }

  void _setSelectedSeason(int seasonNumber) {
    if (!_isSeries || !mounted || seasonNumber == _selectedSeasonNumber) {
      return;
    }

    setState(() {
      _selectedSeasonNumber = seasonNumber;
      _lastFocusedIndexInSeason = null;
    });

    _publishSelectedSeasonBackdrop(seasonNumber);
  }

  bool _publishSelectedSeasonBackdrop(int seasonNumber) {
    if (!_isSeries) {
      return false;
    }

    AggregatedItem? season;

    for (final candidate in _vm.seasons) {
      if (candidate.indexNumber == seasonNumber) {
        season = candidate;
        break;
      }
    }

    final series = _vm.item;

    if (season == null || series == null) {
      return false;
    }

    final backdropItem = season.backdropImageTags.isNotEmpty ? season : series;

    final publishKey = '${season.id}:${backdropItem.id}';

    if (_lastPublishedBackdropKey == publishKey) {
      return true;
    }

    _lastPublishedBackdropKey = publishKey;

    widget.onBackdropItemFocused?.call(backdropItem);

    return true;
  }

  void _scheduleInitialBackdropSync(int seasonNumber) {
    if (!_isSeries ||
        _initialBackdropSyncComplete ||
        _initialBackdropSyncScheduled) {
      return;
    }

    _initialBackdropSyncScheduled = true;

    final scheduledHubKey = _episodeHubKey;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _episodeHubKey != scheduledHubKey) {
        return;
      }

      _initialBackdropSyncScheduled = false;

      if (_initialBackdropSyncComplete) {
        return;
      }

      final currentSeasonNumber = _selectedSeasonNumber ?? seasonNumber;

      if (_publishSelectedSeasonBackdrop(currentSeasonNumber)) {
        _initialBackdropSyncComplete = true;
      }
    });
  }

  bool restoreSelectedSeasonBackdrop() {
    if (!_isSeries) {
      return false;
    }

    final selectedSeasonNumber = _selectedSeasonNumber;

    if (selectedSeasonNumber == null) {
      return false;
    }

    _lastPublishedBackdropKey = null;

    return _publishSelectedSeasonBackdrop(selectedSeasonNumber);
  }

  void _selectSeason(int seasonNumber) {
    _setSelectedSeason(seasonNumber);
  }

  void _showEpisodeContextMenu(BuildContext context, AggregatedItem episode) {
    showContextMenu(
      context,
      episode,
      onChanged: () {
        if (_isSeries) {
          unawaited(_vm.refreshSeriesEpisodes());
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final episodes = _sortedEpisodes;

    final reservingInitialLoad =
        _isSeries && episodes.isEmpty && !_episodesInitialLoadComplete;

    if (episodes.isEmpty && !reservingInitialLoad) {
      return const SizedBox.shrink();
    }

    final seasonNumbers = _seasonNumbersFor(episodes);

    if (_isSeries && seasonNumbers.isEmpty && !reservingInitialLoad) {
      return const SizedBox.shrink();
    }

    final compact = _isCompactMobile(context);

    final selectorHeight = compact ? 44.0 : 40.0;

    final selectorToEpisodes = compact
        ? 18.0
        : NouveauSpacing.seasonSelectorToEpisodes;

    if (reservingInitialLoad) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.linear,
        switchOutCurve: Curves.linear,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: ExcludeFocus(
          key: const ValueKey('nouveau-episodes-reservation'),
          child: SizedBox(height: selectorHeight + selectorToEpisodes + 240),
        ),
      );
    }

    final seasonEpisodes = _episodesForSelectedSeason(episodes);

    _pruneEpisodeFocusNodes(seasonEpisodes);

    final nextUpEpisode = _resolveNextUpEpisode(episodes);

    final showSeasonSelector = _isSeries && seasonNumbers.isNotEmpty;

    int? selectedSeasonNumber;

    if (showSeasonSelector) {
      selectedSeasonNumber = _effectiveSelectedSeason(seasonNumbers);

      _scheduleInitialBackdropSync(selectedSeasonNumber);
    }

    final seerrSeasonStatus = _isSeries
        ? seerrItemSeasonStatus(_vm)
        : const <int, int>{};

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: Column(
        key: ValueKey<String>(
          _isSeason
              ? 'nouveau-season-episodes-grid'
              : 'nouveau-series-episodes-grid-$selectedSeasonNumber',
        ),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSeasonSelector && selectedSeasonNumber != null) ...[
            NouveauSeasonSelector(
              key: _seasonSelectorKey,
              seasonNumbers: seasonNumbers,
              selectedSeasonNumber: selectedSeasonNumber,
              labelBuilder: (seasonNumber) {
                return _seasonName(context, seasonNumber);
              },
              statusBuilder: (seasonNumber) {
                return seerrSeasonStatus[seasonNumber];
              },
              visible: true,
              allowLeftEdgeExit: _navbarIsLeft,
              onNavigateUp: _handleSeasonNavigateUp,
              onNavigateDown: () {
                return _handleSeasonNavigateDown(seasonEpisodes);
              },
              onSeasonActivated: _selectSeason,
            ),
            SizedBox(height: selectorToEpisodes),
          ],

          _buildEpisodesGrid(context, seasonEpisodes, nextUpEpisode),
        ],
      ),
    );
  }

  Widget _buildEpisodesGrid(
    BuildContext context,
    List<AggregatedItem> seasonEpisodes,
    AggregatedItem? nextUpEpisode,
  ) {
    if (seasonEpisodes.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      key: _artworkRailAnchorKey,
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final columns = _columnsFor(context);

        final gap = _isCompactMobile(context)
            ? NouveauSpacing.compactEpisodes.gap
            : (PlatformDetection.isTV
                  ? NouveauSpacing.tvRailItemGap
                  : NouveauSpacing.railItemGap);

        final cardWidth = (availableWidth - (columns - 1) * gap) / columns;

        KeyEventResult Function(FocusNode, KeyEvent) keyHandler(int index) {
          return (node, event) {
            if (!PlatformDetection.isTV || !event.isActionable) {
              return KeyEventResult.ignored;
            }

            if (event.logicalKey.isLeftKey) {
              final atRowStart = index % columns == 0;

              if (atRowStart) {
                if (_navbarIsLeft) {
                  FocusManager.instance.primaryFocus?.focusInDirection(
                    TraversalDirection.left,
                  );
                }

                return KeyEventResult.handled;
              }

              _focusEpisodeAt(seasonEpisodes, index - 1);

              return KeyEventResult.handled;
            }

            if (event.logicalKey.isRightKey) {
              final atRowEnd = index % columns == columns - 1;

              if (!atRowEnd && index + 1 < seasonEpisodes.length) {
                _focusEpisodeAt(seasonEpisodes, index + 1);
              }

              return KeyEventResult.handled;
            }

            if (event.logicalKey.isUpKey) {
              final above = index - columns;

              if (above >= 0) {
                _focusEpisodeAt(seasonEpisodes, above);

                return KeyEventResult.handled;
              }

              return (widget.onNavigateUp?.call() ?? false)
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored;
            }

            if (event.logicalKey.isDownKey) {
              final below = index + columns;

              if (below < seasonEpisodes.length) {
                _focusEpisodeAt(seasonEpisodes, below);

                return KeyEventResult.handled;
              }

              return (widget.onNavigateDown?.call() ?? false)
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored;
            }

            return KeyEventResult.ignored;
          };
        }

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (index, episode) in seasonEpisodes.indexed)
              Focus(
                focusNode: _episodeFocusNode(episode),
                onKeyEvent: keyHandler(index),
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;

                    return SizedBox(
                      width: cardWidth,
                      child: _EpisodeGridTile(
                        episode: episode,
                        imageUrl: _imageUrl(episode),
                        isNextUp: episode.id == nextUpEpisode?.id,
                        isFocused: isFocused,
                        // 30.10, Sid ("quand je clique dessus ça lance
                        // l'épisode au lieu de faire venir dans la
                        // vignette") - tapping a tile selects it (same as
                        // TV D-pad focus landing on it), updating the
                        // preview card above via onEpisodeFocused. Play now
                        // only happens from that preview card's own
                        // thumbnail/Lire button, never straight from the
                        // grid - requestFocus already triggers
                        // _handleEpisodeFocusChange, so this reuses the
                        // exact same path D-pad focus uses, nothing new.
                        onTap: () => _focusEpisodeAt(seasonEpisodes, index),
                        onLongPress: () =>
                            _showEpisodeContextMenu(context, episode),
                        onOpenDetails: () =>
                            _openEpisodeDetails(context, episode),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  int _columnsFor(BuildContext context) {
    if (_isCompactMobile(context)) {
      return 3;
    }

    return PlatformDetection.isTV ? 6 : 5;
  }

  AggregatedItem? _resolveNextUpEpisode(List<AggregatedItem> episodes) {
    for (final episode in episodes) {
      if (!episode.isPlayed) {
        return episode;
      }
    }

    return episodes.isNotEmpty ? episodes.first : null;
  }

  String _seasonName(BuildContext context, int seasonNumber) {
    for (final season in _vm.seasons) {
      if (season.indexNumber != seasonNumber) {
        continue;
      }

      final name = season.name.trim();

      if (name.isNotEmpty) {
        return name;
      }
    }

    return AppLocalizations.of(context).seasonNumber(seasonNumber);
  }

  String? _imageUrl(AggregatedItem item) {
    final tag = item.primaryImageTag;

    if (tag != null && !item.id.startsWith('tmdb:')) {
      return _vm.imageApi.getPrimaryImageUrl(item.id, maxHeight: 360, tag: tag);
    }

    final posterPath = item.rawData['PosterPath'] as String?;

    if (posterPath != null && posterPath.isNotEmpty) {
      return '$seerrPosterBase$posterPath';
    }

    final profilePath = item.rawData['ProfilePath'] as String?;

    if (profilePath != null && profilePath.isNotEmpty) {
      return '$seerrProfileLargeBase$profilePath';
    }

    return null;
  }
}

/// A single grid cell - thumbnail, S/E badge, watched checkmark. Deliberately
/// simple (no title/overview per cell, unlike the old rail cards) - the
/// episode's title/overview live in NouveauEpisodePreviewCard above instead,
/// which this grid drives via onEpisodeFocused/onTap.
class _EpisodeGridTile extends StatelessWidget {
  final AggregatedItem episode;
  final String? imageUrl;
  final bool isNextUp;
  final bool isFocused;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onOpenDetails;

  const _EpisodeGridTile({
    required this.episode,
    required this.imageUrl,
    required this.isNextUp,
    required this.isFocused,
    required this.onTap,
    required this.onLongPress,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final code = episode.indexNumber != null ? 'E${episode.indexNumber}' : '';
    final watched = episode.isPlayed;
    final progress = episode.playedPercentage;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                imageUrl != null
                    ? OfflineAwareImage(imageUrl: imageUrl!, fit: BoxFit.cover)
                    : ColoredBox(color: Colors.white.withValues(alpha: 0.1)),

                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: watched ? 0.45 : 0.25),
                      ],
                      stops: const [0.6, 1.0],
                    ),
                  ),
                ),

                if (watched)
                  ColoredBox(color: Colors.black.withValues(alpha: 0.35)),

                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                if (watched)
                  const Positioned(
                    bottom: 4,
                    right: 4,
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 16,
                    ),
                  )
                else if (isNextUp)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        AppLocalizations.of(context).nextUp,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                if (!watched && progress != null && progress > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: (progress / 100).clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),

                if (isFocused)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

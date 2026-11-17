import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../../data/services/plugin_sync_service.dart';
import '../../../../../data/services/seerr/seerr_api_models.dart';
import '../../../../../data/viewmodels/item_detail_view_model.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../preference/preference_constants.dart';
import '../../../../../preference/user_preferences.dart';
import '../../../../../util/platform_detection.dart';
import '../../../../widgets/navigation_layout.dart';
import '../../../../widgets/seerr/seerr_item_status.dart';
import '../shared/nouveau_spacing.dart';
import 'nouveau_discovery_card.dart';
import 'nouveau_discovery_rail.dart';

class NouveauDiscoverySection extends StatefulWidget {
  final ItemDetailViewModel viewModel;

  final UserPreferences prefs;

  final bool Function()? onNavigateUp;

  final bool Function()? onNavigateDown;

  final ValueChanged<GlobalKey>? onRevealRequested;

  const NouveauDiscoverySection({
    super.key,
    required this.viewModel,
    required this.prefs,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onRevealRequested,
  });

  static bool supportsItem(AggregatedItem item) {
    return item.type == 'Movie' || item.type == 'Series';
  }

  static bool _seerrExpected(ItemDetailViewModel viewModel) {
    final item = viewModel.item;

    if (item == null || !supportsItem(item)) {
      return false;
    }

    if (!GetIt.instance<PluginSyncService>().seerrAvailable) {
      return false;
    }

    return (item.tmdbId?.isNotEmpty ?? false) ||
        (item.imdbId?.isNotEmpty ?? false);
  }

  static bool _seerrRelatedResolved(ItemDetailViewModel viewModel) {
    if (!_seerrExpected(viewModel)) {
      return true;
    }

    final seerr = viewModel.seerr;

    if (seerr == null) {
      return false;
    }

    if (seerr.state.error != null) {
      return true;
    }

    return seerr.relatedLoadComplete;
  }

  // 30.10, Sid : « la partie "similaire" on peut la supprimer tout court, je
  // vais jamais dessus... en plus ils ont pas grand chose à voir ». Mise en
  // sommeil par un `return false` unique, en gardant tout le reste du code
  // « pour rester réversible d'une seule ligne si elle change d'avis ».
  //
  // 17.11 : elle change d'avis, et pour une raison precise - ces rangees ne
  // valaient rien parce qu'elles venaient d'un service de requetes qui n'a
  // jamais repondu (le plugin Moonfin, absent de son Emby). Patoune TV repond
  // desormais, les similaires viennent de TMDB : « tu peux remettre du coup ».
  // Logique d'origine restauree telle quelle.
  static bool shouldInclude(ItemDetailViewModel viewModel) {
    final item = viewModel.item;

    if (item == null || !supportsItem(item)) {
      return false;
    }

    // 17.11 : la rangée ne vient plus que du service de requêtes (voir
    // _related), donc les similaires d'Emby ne doivent plus la faire
    // apparaître à eux seuls - sans quoi elle s'afficherait vide.
    if (!_seerrExpected(viewModel)) {
      return false;
    }

    if (!_seerrRelatedResolved(viewModel)) {
      return true;
    }

    final state = seerrItemTabState(viewModel);

    return state != null &&
        (state.similar.isNotEmpty || state.recommendations.isNotEmpty);
  }

  @override
  State<NouveauDiscoverySection> createState() =>
      NouveauDiscoverySectionState();
}

class NouveauDiscoverySectionState extends State<NouveauDiscoverySection>
    with TickerProviderStateMixin {
  static const Duration _skeletonGracePeriod = Duration(milliseconds: 450);

  static const Duration _railFadeDuration = Duration(milliseconds: 220);

  late final AnimationController _relatedOpacityController;

  late final AnimationController _recommendationsOpacityController;

  // 26.10 : type mis à jour vers NouveauDiscoveryRailState (grille Wrap, plus
  // de LockedFocusRow) - requestFocusFromMemory() y existe toujours, même
  // rôle qu'avant. hubKey/scrollController retirés avec le rail lui-même,
  // plus rien à leur passer ici.
  final GlobalKey<NouveauDiscoveryRailState> _relatedRowKey =
      GlobalKey<NouveauDiscoveryRailState>();

  final GlobalKey<NouveauDiscoveryRailState> _recommendationsRowKey =
      GlobalKey<NouveauDiscoveryRailState>();

  final GlobalKey _relatedRevealKey = GlobalKey();

  final GlobalKey _recommendationsRevealKey = GlobalKey();

  Timer? _skeletonTimer;

  bool _skeletonDelayElapsed = false;

  bool _relatedSkeletonShown = false;

  bool _recommendationsSkeletonShown = false;

  bool _relatedCardsShown = false;

  bool _recommendationsCardsShown = false;

  String? _trackedItemId;

  List<AggregatedItem> _baseRelatedSnapshot = const [];

  bool _baseRelatedCaptured = false;

  ItemDetailViewModel get _vm => widget.viewModel;

  bool _isCompactMobile(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return !PlatformDetection.isTV && size.shortestSide < 600;
  }

  GlobalKey? get topRevealKey {
    if (_related.isNotEmpty) {
      return _relatedRevealKey;
    }

    if (_recommendations.isNotEmpty) {
      return _recommendationsRevealKey;
    }

    return null;
  }

  GlobalKey? get bottomRevealKey {
    if (_recommendations.isNotEmpty) {
      return _recommendationsRevealKey;
    }

    if (_related.isNotEmpty) {
      return _relatedRevealKey;
    }

    return null;
  }

  @override
  void initState() {
    super.initState();

    _relatedOpacityController = AnimationController(
      vsync: this,
      duration: _railFadeDuration,
    );

    _recommendationsOpacityController = AnimationController(
      vsync: this,
      duration: _railFadeDuration,
    );

    _trackedItemId = _vm.item?.id;

    _captureBaseRelatedIfAvailable();

    _initializeContent();

    _vm.addListener(_onViewModelChanged);

    _startSkeletonGracePeriod();
  }

  @override
  void didUpdateWidget(covariant NouveauDiscoverySection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.viewModel, widget.viewModel)) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);

      widget.viewModel.addListener(_onViewModelChanged);

      _resetForItem();
    }
  }

  @override
  void dispose() {
    _skeletonTimer?.cancel();

    _vm.removeListener(_onViewModelChanged);

    _relatedOpacityController.dispose();

    _recommendationsOpacityController.dispose();

    super.dispose();
  }

  void _initializeContent() {
    if (_related.isNotEmpty) {
      _relatedCardsShown = true;

      _relatedOpacityController.forward(from: 0);
    }

    if (_recommendations.isNotEmpty) {
      _recommendationsCardsShown = true;

      _recommendationsOpacityController.forward(from: 0);
    }
  }

  void _onViewModelChanged() {
    if (!mounted) {
      return;
    }

    final itemId = _vm.item?.id;

    if (itemId != _trackedItemId) {
      _resetForItem();
      return;
    }

    _captureBaseRelatedIfAvailable();

    _syncRailContent();

    setState(() {});
  }

  void _resetForItem() {
    _skeletonTimer?.cancel();

    _trackedItemId = _vm.item?.id;

    _baseRelatedSnapshot = const [];

    _baseRelatedCaptured = false;

    _skeletonDelayElapsed = false;

    _relatedSkeletonShown = false;

    _recommendationsSkeletonShown = false;

    _relatedCardsShown = false;

    _recommendationsCardsShown = false;

    _relatedOpacityController
      ..stop()
      ..value = 0;

    _recommendationsOpacityController
      ..stop()
      ..value = 0;

    _captureBaseRelatedIfAvailable();

    _initializeContent();

    _startSkeletonGracePeriod();

    if (mounted) {
      setState(() {});
    }
  }

  void _startSkeletonGracePeriod() {
    _skeletonTimer?.cancel();

    _skeletonTimer = Timer(_skeletonGracePeriod, () {
      if (!mounted) {
        return;
      }

      _skeletonDelayElapsed = true;

      final related = _related;

      final recommendations = _recommendations;

      final baseWaiting = !_vm.similarInitialLoadComplete;

      final seerrWaiting = _seerrExpected && !_seerrRelatedResolved;

      var changed = false;

      if (related.isEmpty &&
          (baseWaiting || seerrWaiting) &&
          !_relatedCardsShown &&
          !_relatedSkeletonShown) {
        _relatedSkeletonShown = true;

        _relatedOpacityController.forward(from: 0);

        changed = true;
      }

      if (recommendations.isEmpty &&
          seerrWaiting &&
          !_recommendationsCardsShown &&
          !_recommendationsSkeletonShown) {
        _recommendationsSkeletonShown = true;

        _recommendationsOpacityController.forward(from: 0);

        changed = true;
      }

      if (changed) {
        setState(() {});
      }
    });
  }

  void _syncRailContent() {
    final related = _related;

    final recommendations = _recommendations;

    final hasRelated = related.isNotEmpty;

    final hasRecommendations = recommendations.isNotEmpty;

    if (hasRelated && !_relatedCardsShown) {
      final replacingSkeleton = _relatedSkeletonShown;

      _relatedCardsShown = true;

      _relatedSkeletonShown = false;

      if (replacingSkeleton) {
        _relatedOpacityController
          ..stop()
          ..value = 1;
      } else {
        _relatedOpacityController.forward(from: 0);
      }
    }

    if (hasRecommendations && !_recommendationsCardsShown) {
      final replacingSkeleton = _recommendationsSkeletonShown;

      _recommendationsCardsShown = true;

      _recommendationsSkeletonShown = false;

      if (replacingSkeleton) {
        _recommendationsOpacityController
          ..stop()
          ..value = 1;
      } else {
        _recommendationsOpacityController.forward(from: 0);
      }
    }

    final baseWaiting = !_vm.similarInitialLoadComplete;

    final seerrWaiting = _seerrExpected && !_seerrRelatedResolved;

    if (!hasRelated && !baseWaiting && !seerrWaiting && _relatedSkeletonShown) {
      _relatedSkeletonShown = false;

      _relatedOpacityController
        ..stop()
        ..value = 0;
    }

    if (!hasRecommendations && !seerrWaiting && _recommendationsSkeletonShown) {
      _recommendationsSkeletonShown = false;

      _recommendationsOpacityController
        ..stop()
        ..value = 0;
    }

    if (!_skeletonDelayElapsed) {
      return;
    }

    if (!hasRelated &&
        (baseWaiting || seerrWaiting) &&
        !_relatedCardsShown &&
        !_relatedSkeletonShown) {
      _relatedSkeletonShown = true;

      _relatedOpacityController.forward(from: 0);
    }

    if (!hasRecommendations &&
        seerrWaiting &&
        !_recommendationsCardsShown &&
        !_recommendationsSkeletonShown) {
      _recommendationsSkeletonShown = true;

      _recommendationsOpacityController.forward(from: 0);
    }
  }

  bool get _seerrExpected {
    final item = _vm.item;

    if (item == null ||
        !NouveauDiscoverySection.supportsItem(item) ||
        !GetIt.instance<PluginSyncService>().seerrAvailable) {
      return false;
    }

    return (item.tmdbId?.isNotEmpty ?? false) ||
        (item.imdbId?.isNotEmpty ?? false);
  }

  bool get _seerrRelatedResolved {
    if (!_seerrExpected) {
      return true;
    }

    final seerr = _vm.seerr;

    if (seerr == null) {
      return false;
    }

    if (seerr.state.error != null) {
      return true;
    }

    return seerr.relatedLoadComplete;
  }

  bool get _navbarIsLeft =>
      widget.prefs.get(UserPreferences.navbarPosition) == NavbarPosition.left;

  void _handleLeftEdge() {
    NavigationLayout.focusNavbarNotifier.value?.call();
  }

  void _captureBaseRelatedIfAvailable() {
    if (_baseRelatedCaptured || _vm.similar.isEmpty) {
      return;
    }

    _baseRelatedSnapshot = _dedupeBaseRelated(_vm.similar);

    _baseRelatedCaptured = true;
  }

  List<AggregatedItem> _dedupeBaseRelated(List<AggregatedItem> source) {
    final currentItem = _vm.item;

    final currentKeys = currentItem == null
        ? const <String>{}
        : _identityKeys(currentItem);

    final seen = <String>{};

    final result = <AggregatedItem>[];

    for (final item in source) {
      final keys = _identityKeys(item);

      if (_sharesIdentity(keys, currentKeys) || _sharesIdentity(keys, seen)) {
        continue;
      }

      seen.addAll(keys);

      result.add(item);
    }

    return List<AggregatedItem>.unmodifiable(result);
  }

  List<AggregatedItem> get _baseRelated {
    if (_baseRelatedCaptured) {
      return _baseRelatedSnapshot;
    }

    return _dedupeBaseRelated(_vm.similar);
  }

  int get _protectedBaseCount =>
      NouveauSpacing.discoveryVisibleItemCount.ceil();

  List<AggregatedItem> get _protectedBaseRelated {
    return _baseRelated.take(_protectedBaseCount).toList(growable: false);
  }

  List<AggregatedItem> get _recommendations {
    final state = seerrItemTabState(_vm);

    if (state == null || state.recommendations.isEmpty) {
      return const [];
    }

    final protectedKeys = <String>{
      for (final item in _protectedBaseRelated) ..._identityKeys(item),
    };

    final currentItem = _vm.item;

    final currentKeys = currentItem == null
        ? const <String>{}
        : _identityKeys(currentItem);

    final seen = <String>{};

    final result = <AggregatedItem>[];

    for (final item in state.recommendations) {
      final converted = _seerrItemToAggregated(item);

      final keys = _identityKeys(converted);

      if (_sharesIdentity(keys, currentKeys) ||
          _sharesIdentity(keys, protectedKeys) ||
          _sharesIdentity(keys, seen)) {
        continue;
      }

      seen.addAll(keys);

      result.add(converted);
    }

    return result;
  }

  /// 17.11, Sid : « j'ai que 20 propositions, qui viennent toutes de mon emby
  /// [...] aucun intérêt qu'il me propose des similaires qui n'en sont pas et
  /// qu'en plus certains j'ai déjà vu. Ils restent simplement dans mon emby ».
  ///
  /// La rangée empilait trois sources dans cet ordre : les similaires d'Emby
  /// « protégés » (toujours en tête, donc les seuls visibles sans faire
  /// défiler), la suite de ceux d'Emby, puis ceux de TMDB tout à la fin. Or
  /// Emby ne peut proposer que ce qu'il contient déjà : la rangée ne montrait
  /// donc jamais autre chose que sa propre bibliothèque, et les suggestions
  /// TMDB étaient reléguées hors de vue.
  ///
  /// Elle ne vient plus que du service de requêtes. Sans réponse de sa part,
  /// la rangée disparaît (voir shouldInclude) plutôt que de retomber sur une
  /// liste sans intérêt. `_protectedBaseRelated` reste utilisé par
  /// `_recommendations` pour dédoublonner les deux rangées entre elles.
  List<AggregatedItem> get _related {
    final state = seerrItemTabState(_vm);

    if (state == null) {
      return const [];
    }

    final recommendations = _recommendations;

    final recommendationKeys = <String>{
      for (final item in recommendations) ..._identityKeys(item),
    };

    final result = <AggregatedItem>[];

    final currentItem = _vm.item;

    final currentKeys = currentItem == null
        ? const <String>{}
        : _identityKeys(currentItem);

    final seen = <String>{for (final item in result) ..._identityKeys(item)};

    // Source API calls this collection "similar". Inside Nouveau Discovery
    // it is treated as the related-content rail.
    for (final item in state.similar) {
      final converted = _seerrItemToAggregated(item);

      final keys = _identityKeys(converted);

      if (_sharesIdentity(keys, currentKeys) ||
          _sharesIdentity(keys, seen) ||
          _sharesIdentity(keys, recommendationKeys)) {
        continue;
      }

      seen.addAll(keys);

      result.add(converted);
    }

    return result;
  }

  Set<String> _identityKeys(AggregatedItem item) {
    final keys = <String>{};

    final mediaType = switch (item.type) {
      'Series' => 'tv',
      'Movie' => 'movie',
      final type? => type.toLowerCase(),
      null => 'unknown',
    };

    final tmdbId = item.tmdbId?.trim();

    if (tmdbId != null && tmdbId.isNotEmpty) {
      keys.add('tmdb:$mediaType:$tmdbId');
    }

    final normalizedTitle = item.name.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    if (normalizedTitle.isNotEmpty) {
      final year = item.productionYear?.toString() ?? '';

      keys.add('title:$mediaType:$normalizedTitle|year:$year');
    }

    if (keys.isEmpty) {
      keys.add('server:${item.serverId}|id:${item.id}');
    }

    return keys;
  }

  bool _sharesIdentity(Set<String> itemKeys, Set<String> knownKeys) {
    for (final key in itemKeys) {
      if (knownKeys.contains(key)) {
        return true;
      }
    }

    return false;
  }

  AggregatedItem _seerrItemToAggregated(SeerrDiscoverItem item) {
    final mediaType = item.mediaType ?? 'movie';

    final date = item.releaseDate ?? item.firstAirDate;

    final year = date != null && date.length >= 4
        ? int.tryParse(date.substring(0, 4))
        : null;

    return AggregatedItem(
      id: item.id.toString(),
      serverId: 'seerr',
      rawData: {
        'Name': item.displayTitle,
        'Overview': item.overview,
        'Type': mediaType == 'tv' ? 'Series' : 'Movie',
        'ProviderIds': {'Tmdb': item.id.toString()},
        'PosterPath': item.posterPath,
        'BackdropPath': item.backdropPath,
        'ProductionYear': ?year,
        'PremiereDate': ?date,
        'CommunityRating': item.voteAverage,
        'SeerrMediaType': mediaType,
        'SeerrStatus': item.mediaInfo?.status,
        'UserData': const {'Played': false, 'IsFavorite': false},
        'MediaSources': const [],
        'MediaStreams': const [],
        'CanDelete': false,
      },
    );
  }

  bool get canFocusTop {
    if (!mounted) {
      return false;
    }

    if (_related.isNotEmpty) {
      return _relatedRowKey.currentState != null;
    }

    if (_recommendations.isNotEmpty) {
      return _recommendationsRowKey.currentState != null;
    }

    return false;
  }

  bool focusTop() {
    if (_related.isNotEmpty && _relatedRowKey.currentState != null) {
      _relatedRowKey.currentState!.requestFocusFromMemory();

      return true;
    }

    if (_recommendations.isNotEmpty &&
        _recommendationsRowKey.currentState != null) {
      _recommendationsRowKey.currentState!.requestFocusFromMemory();

      return true;
    }

    return false;
  }

  bool focusBottom() {
    if (_recommendations.isNotEmpty &&
        _recommendationsRowKey.currentState != null) {
      _recommendationsRowKey.currentState!.requestFocusFromMemory();

      return true;
    }

    if (_related.isNotEmpty && _relatedRowKey.currentState != null) {
      _relatedRowKey.currentState!.requestFocusFromMemory();

      return true;
    }

    return false;
  }

  bool _focusRelated() {
    if (_related.isEmpty || _relatedRowKey.currentState == null) {
      return false;
    }

    _relatedRowKey.currentState!.requestFocusFromMemory();

    widget.onRevealRequested?.call(_relatedRevealKey);

    return true;
  }

  bool _focusRecommendations() {
    if (_recommendations.isEmpty ||
        _recommendationsRowKey.currentState == null) {
      return false;
    }

    _recommendationsRowKey.currentState!.requestFocusFromMemory();

    widget.onRevealRequested?.call(_recommendationsRevealKey);

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final related = _related;

    final recommendations = _recommendations;

    final baseWaiting = !_vm.similarInitialLoadComplete;

    final seerrWaiting = _seerrExpected && !_seerrRelatedResolved;

    final showRelated = related.isNotEmpty || baseWaiting || seerrWaiting;

    final showRecommendations =
        _seerrExpected && (recommendations.isNotEmpty || seerrWaiting);

    if (!showRelated && !showRecommendations) {
      return const SizedBox.shrink();
    }

    final compact = _isCompactMobile(context);

    final interRailSpacing = compact
        ? NouveauSpacing.mobileSectionGap
        : NouveauSpacing.sectionGap;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showRelated)
          KeyedSubtree(
            key: _relatedRevealKey,
            child: NouveauDiscoveryRail(
              key: _relatedRowKey,
              // Existing localization key kept because changing generated
              // localization API is outside this UI cleanup.
              title: l10n.similar,
              items: related,
              showSkeleton: _relatedSkeletonShown && related.isEmpty,
              opacity: _relatedOpacityController,
              onNavigateUp: () {
                return widget.onNavigateUp?.call() ?? false;
              },
              onNavigateDown: () {
                if (_focusRecommendations()) {
                  return true;
                }

                return widget.onNavigateDown?.call() ?? false;
              },
              onTap: (item) {
                NouveauDiscoveryCard.openItem(context, item);
              },
              onLeftEdge: _navbarIsLeft ? _handleLeftEdge : null,
              itemBuilder: (context, item, width, isFocused) {
                return NouveauDiscoveryCard(
                  item: item,
                  imageApi: _vm.imageApi,
                  prefs: widget.prefs,
                  width: width,
                  isFocused: isFocused,
                );
              },
            ),
          ),

        if (showRelated && showRecommendations)
          SizedBox(height: interRailSpacing),

        if (showRecommendations)
          KeyedSubtree(
            key: _recommendationsRevealKey,
            child: NouveauDiscoveryRail(
              key: _recommendationsRowKey,
              title: l10n.recommendations,
              items: recommendations,
              showSkeleton:
                  _recommendationsSkeletonShown && recommendations.isEmpty,
              opacity: _recommendationsOpacityController,
              onNavigateUp: () {
                if (_focusRelated()) {
                  return true;
                }

                return widget.onNavigateUp?.call() ?? false;
              },
              onNavigateDown: () {
                return widget.onNavigateDown?.call() ?? false;
              },
              onTap: (item) {
                NouveauDiscoveryCard.openItem(context, item);
              },
              onLeftEdge: _navbarIsLeft ? _handleLeftEdge : null,
              itemBuilder: (context, item, width, isFocused) {
                return NouveauDiscoveryCard(
                  item: item,
                  imageApi: _vm.imageApi,
                  prefs: widget.prefs,
                  width: width,
                  isFocused: isFocused,
                );
              },
            ),
          ),
      ],
    );
  }
}

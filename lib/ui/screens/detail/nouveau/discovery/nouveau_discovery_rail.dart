import 'package:flutter/material.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../../util/focus/dpad_keys.dart';
import '../../../../../util/platform_detection.dart';
import '../shared/nouveau_spacing.dart';

// 26.10, Sid ("dans l'idéal, je ne veux pas de scroll vers la droite, nulle
// part. Le scroll c'est chiant" + "les vignettes pour les similaires sont
// trop petites, ça rend le badge trop grand") - remplace le rail qui
// défilait horizontalement (LockedFocusRow, nombre de cartes forcé à tenir
// dans la largeur - NouveauSpacing.discoveryVisibleItemCount, donnant des
// vignettes minuscules sur un grand écran) par une vraie grille qui
// s'enroule (Wrap) : largeur de carte FIXE et raisonnable, autant de
// colonnes que la largeur réelle le permet, ça déborde sur une ligne de
// plus plutôt que de rétrécir chaque carte. rowKey/hubKey/controller
// retirés : l'appelant (nouveau_discovery_section.dart) utilisait rowKey
// pour appeler .currentState!.requestFocusFromMemory() sur l'ancien
// LockedFocusRowState - un GlobalKey<NouveauDiscoveryRailState> passé via
// le `key:` standard du widget fait exactement ça maintenant (voir
// requestFocusFromMemory() plus bas), plus besoin d'un champ séparé.
class NouveauDiscoveryRail extends StatefulWidget {
  final String title;
  final List<AggregatedItem> items;
  final bool showSkeleton;
  final Animation<double> opacity;

  final bool Function() onNavigateUp;
  final bool Function() onNavigateDown;

  final VoidCallback? onLeftEdge;

  final ValueChanged<AggregatedItem> onTap;

  final Widget Function(
    BuildContext context,
    AggregatedItem item,
    double width,
    bool isFocused,
  )
  itemBuilder;

  const NouveauDiscoveryRail({
    super.key,
    required this.title,
    required this.items,
    required this.showSkeleton,
    required this.opacity,
    required this.onNavigateUp,
    required this.onNavigateDown,
    this.onLeftEdge,
    required this.onTap,
    required this.itemBuilder,
  });

  @override
  State<NouveauDiscoveryRail> createState() => NouveauDiscoveryRailState();
}

class NouveauDiscoveryRailState extends State<NouveauDiscoveryRail> {
  // Cible raisonnable pour une vignette poster (2:3), bornée - même esprit
  // que les grilles d'affiches ailleurs dans l'appli, indépendante du
  // nombre d'items ou de la largeur d'écran (contrairement à l'ancien
  // calcul "largeur / nombre fixe de cartes").
  static const double _targetCardWidth = 150.0;
  static const double _minCardWidth = 120.0;
  static const double _maxCardWidth = 190.0;

  final Map<int, FocusNode> _focusNodes = {};
  int? _lastFocusedIndex;

  FocusNode _nodeFor(int index) => _focusNodes.putIfAbsent(index, () {
    final node = FocusNode(debugLabel: 'discovery:$index');
    node.addListener(() {
      if (node.hasFocus) {
        _lastFocusedIndex = index;
      }
    });
    return node;
  });

  /// Appelé de l'extérieur (voir nouveau_discovery_section.dart, même rôle
  /// que l'ancien LockedFocusRowState.requestFocusFromMemory()) pour rendre
  /// le focus au dernier item réellement focusé plutôt que de toujours
  /// repartir du premier.
  bool requestFocusFromMemory() {
    if (widget.items.isEmpty) {
      return false;
    }
    final index = (_lastFocusedIndex ?? 0).clamp(0, widget.items.length - 1);
    _nodeFor(index).requestFocus();
    return true;
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  bool _isCompactMobile(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return !PlatformDetection.isTV && size.shortestSide < 600;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final compact = _isCompactMobile(context);
        final layout = _layoutFor(availableWidth, compact: compact);
        final textTheme = Theme.of(context).textTheme;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: compact
                  ? textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    )
                  : textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(
              height: compact
                  ? NouveauSpacing.mobileTitleToContent
                  : NouveauSpacing.titleToContent,
            ),
            FadeTransition(
              opacity: widget.opacity,
              child: widget.items.isNotEmpty
                  ? _buildGrid(context, layout)
                  : widget.showSkeleton
                  ? IgnorePointer(child: _buildSkeletonGrid(layout))
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  _DiscoveryGridLayout _layoutFor(double availableWidth, {required bool compact}) {
    final cardWidth = compact
        ? NouveauSpacing.compactDiscovery.itemWidth(availableWidth)
        : _targetCardWidth.clamp(_minCardWidth, _maxCardWidth);
    final cardSpacing = compact ? NouveauSpacing.compactDiscovery.gap : 14.0;
    final posterHeight = cardWidth * 3 / 2;
    const captionGap = 9.0;
    const captionHeight = 42.0;

    final itemsPerLine = ((availableWidth + cardSpacing) / (cardWidth + cardSpacing))
        .floor()
        .clamp(1, 1000);

    return _DiscoveryGridLayout(
      cardWidth: cardWidth,
      cardSpacing: cardSpacing,
      posterHeight: posterHeight,
      cardHeight: posterHeight + captionGap + captionHeight,
      itemsPerLine: itemsPerLine,
    );
  }

  Widget _buildGrid(BuildContext context, _DiscoveryGridLayout layout) {
    final items = widget.items;

    KeyEventResult Function(FocusNode, KeyEvent) keyHandler(int i) {
      return (node, event) {
        if (!PlatformDetection.isTV || !event.isActionable) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey.isLeftKey) {
          final atLineStart = i % layout.itemsPerLine == 0;
          if (atLineStart) {
            widget.onLeftEdge?.call();
            return KeyEventResult.handled;
          }
          _nodeFor(i - 1).requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey.isRightKey) {
          final atLineEnd = i % layout.itemsPerLine == layout.itemsPerLine - 1;
          if (!atLineEnd && i + 1 < items.length) {
            _nodeFor(i + 1).requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey.isUpKey) {
          final above = i - layout.itemsPerLine;
          if (above >= 0) {
            _nodeFor(above).requestFocus();
            return KeyEventResult.handled;
          }
          return widget.onNavigateUp() ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (event.logicalKey.isDownKey) {
          final below = i + layout.itemsPerLine;
          if (below < items.length) {
            _nodeFor(below).requestFocus();
            return KeyEventResult.handled;
          }
          return widget.onNavigateDown() ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      };
    }

    return Wrap(
      spacing: layout.cardSpacing,
      runSpacing: layout.cardSpacing,
      children: [
        for (final (i, item) in items.indexed)
          Focus(
            focusNode: _nodeFor(i),
            onKeyEvent: keyHandler(i),
            child: Builder(
              builder: (context) {
                final isFocused = Focus.of(context).hasFocus;
                return GestureDetector(
                  onTap: () => widget.onTap(item),
                  child: widget.itemBuilder(context, item, layout.cardWidth, isFocused),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSkeletonGrid(_DiscoveryGridLayout layout) {
    // Une seule ligne suffit comme aperçu de chargement - la vraie grille
    // prend sa hauteur réelle une fois les items chargés.
    final placeholderCount = layout.itemsPerLine;

    return Wrap(
      spacing: layout.cardSpacing,
      runSpacing: layout.cardSpacing,
      children: [
        for (var i = 0; i < placeholderCount; i++)
          _DiscoveryPlaceholderCard(
            width: layout.cardWidth,
            posterHeight: layout.posterHeight,
            totalHeight: layout.cardHeight,
            showCaption: true,
          ),
      ],
    );
  }
}

class _DiscoveryPlaceholderCard extends StatelessWidget {
  final double width;
  final double posterHeight;
  final double totalHeight;
  final bool showCaption;

  const _DiscoveryPlaceholderCard({
    required this.width,
    required this.posterHeight,
    required this.totalHeight,
    required this.showCaption,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurface;

    if (!showCaption) {
      return Container(
        width: width,
        height: posterHeight,
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: foreground.withValues(alpha: 0.08)),
        ),
      );
    }

    return SizedBox(
      width: width,
      height: totalHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: width,
            height: posterHeight,
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: foreground.withValues(alpha: 0.08)),
            ),
          ),
          const SizedBox(height: 9),
          Center(
            child: Container(
              width: width * 0.72,
              height: 12,
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryGridLayout {
  final double cardWidth;
  final double cardSpacing;
  final double posterHeight;
  final double cardHeight;
  final int itemsPerLine;

  const _DiscoveryGridLayout({
    required this.cardWidth,
    required this.cardSpacing,
    required this.posterHeight,
    required this.cardHeight,
    required this.itemsPerLine,
  });
}

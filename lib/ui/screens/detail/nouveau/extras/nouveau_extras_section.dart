import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../preference/user_preferences.dart';
import '../../../../../preference/preference_constants.dart';
import '../../../../../util/focus/dpad_keys.dart';
import '../../../../../util/platform_detection.dart';
import '../../../../widgets/navigation_layout.dart';
import '../../../../navigation/destinations.dart';
import '../shared/nouveau_media_rail_card.dart';
import '../shared/nouveau_spacing.dart';

// 26.10, Sid ("après tu peux attaquer toutes les zones de scroll") - même
// conversion que nouveau_discovery_rail.dart : LockedFocusRow (scroll
// horizontal forcé) remplacé par une vraie grille Wrap, largeur de carte
// fixe, déborde sur une ligne de plus plutôt que de scroller.
class NouveauExtrasSection extends StatefulWidget {
  const NouveauExtrasSection({
    super.key,
    required this.items,
    required this.imageApi,
    required this.prefs,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final List<AggregatedItem> items;
  final ImageApi imageApi;
  final UserPreferences prefs;
  final bool Function()? onNavigateUp;
  final bool Function()? onNavigateDown;

  @override
  State<NouveauExtrasSection> createState() => NouveauExtrasSectionState();
}

class NouveauExtrasSectionState extends State<NouveauExtrasSection> {
  final Map<int, FocusNode> _focusNodes = {};
  int? _lastFocusedIndex;

  FocusNode _nodeFor(int index) => _focusNodes.putIfAbsent(index, () {
    final node = FocusNode(debugLabel: 'extras:$index');
    node.addListener(() {
      if (node.hasFocus) {
        _lastFocusedIndex = index;
      }
    });
    return node;
  });

  bool _isCompactMobile(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return !PlatformDetection.isTV && size.shortestSide < 600;
  }

  void _openItem(AggregatedItem item) {
    context.push(Destinations.item(item.id, serverId: item.serverId));
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }

    super.dispose();
  }

  bool get canFocusTop => mounted && widget.items.isNotEmpty;

  bool get _navbarIsLeft =>
      widget.prefs.get(UserPreferences.navbarPosition) == NavbarPosition.left;

  void _handleLeftEdge() {
    NavigationLayout.focusNavbarNotifier.value?.call();
  }

  bool focusTop() {
    if (!canFocusTop) {
      return false;
    }

    final index = (_lastFocusedIndex ?? 0).clamp(0, widget.items.length - 1);
    _nodeFor(index).requestFocus();

    return true;
  }

  bool focusBottom() => focusTop();

  String? _imageUrl(AggregatedItem item) {
    final tag = item.primaryImageTag;

    if (tag == null || tag.isEmpty) {
      return null;
    }

    return widget.imageApi.getPrimaryImageUrl(
      item.id,
      maxHeight: 500,
      tag: tag,
    );
  }

  double _progress(AggregatedItem item) {
    final percentage = item.playedPercentage;

    if (percentage == null || !percentage.isFinite) {
      return 0;
    }

    return (percentage / 100).clamp(0.0, 1.0).toDouble();
  }

  _ExtrasLayout _layoutFor(BuildContext context, double availableWidth) {
    final compact = _isCompactMobile(context);

    final double cardWidth;
    final double cardSpacing;
    if (compact) {
      final metrics = NouveauSpacing.compactEpisodes;
      cardWidth = metrics.itemWidth(availableWidth);
      cardSpacing = metrics.gap;
    } else {
      cardWidth = NouveauMediaRailMetrics.cardWidth(availableWidth);
      cardSpacing = NouveauMediaRailMetrics.itemGap;
    }

    final artworkHeight = compact
        ? cardWidth * 9 / 16
        : NouveauMediaRailMetrics.artworkHeight(cardWidth);

    final itemsPerLine = ((availableWidth + cardSpacing) / (cardWidth + cardSpacing))
        .floor()
        .clamp(1, 1000);

    return _ExtrasLayout(
      cardWidth: cardWidth,
      artworkHeight: artworkHeight,
      cardSpacing: cardSpacing,
      compact: compact,
      itemsPerLine: itemsPerLine,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    final foreground = AppColorScheme.onSurface;

    final l10n = AppLocalizations.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final layout = _layoutFor(context, availableWidth);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.extras,
              style: layout.compact
                  ? theme.textTheme.titleLarge?.copyWith(
                      color: foreground,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    )
                  : theme.textTheme.titleLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
            ),

            SizedBox(
              height: layout.compact
                  ? NouveauSpacing.mobileTitleToContent
                  : NouveauSpacing.titleToContent,
            ),

            _buildGrid(context, layout),
          ],
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context, _ExtrasLayout layout) {
    final items = widget.items;

    KeyEventResult Function(FocusNode, KeyEvent) keyHandler(int i) {
      return (node, event) {
        if (!PlatformDetection.isTV || !event.isActionable) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey.isLeftKey) {
          final atLineStart = i % layout.itemsPerLine == 0;
          if (atLineStart) {
            if (_navbarIsLeft) {
              _handleLeftEdge();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
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
          return (widget.onNavigateUp?.call() ?? false)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey.isDownKey) {
          final below = i + layout.itemsPerLine;
          if (below < items.length) {
            _nodeFor(below).requestFocus();
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
      spacing: layout.cardSpacing,
      runSpacing: layout.cardSpacing,
      children: [
        for (final (i, item) in items.indexed)
          Focus(
            focusNode: _nodeFor(i),
            onKeyEvent: keyHandler(i),
            child: Builder(
              builder: (context) => NouveauMediaRailCard(
                imageUrl: _imageUrl(item),
                title: item.name.trim(),
                subtitle: item.subtitle,
                placeholderLabel: item.name.trim(),
                width: layout.cardWidth,
                artworkHeight: layout.artworkHeight,
                isFocused: Focus.of(context).hasFocus,
                isPlayed: item.isPlayed,
                progress: _progress(item),
                onTap: () => _openItem(item),
              ),
            ),
          ),
      ],
    );
  }
}

class _ExtrasLayout {
  final double cardWidth;
  final double artworkHeight;
  final double cardSpacing;
  final bool compact;
  final int itemsPerLine;

  const _ExtrasLayout({
    required this.cardWidth,
    required this.artworkHeight,
    required this.cardSpacing,
    required this.compact,
    required this.itemsPerLine,
  });
}

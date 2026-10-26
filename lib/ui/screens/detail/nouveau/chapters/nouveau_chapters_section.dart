import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../preference/user_preferences.dart';
import '../../../../../preference/preference_constants.dart';
import '../../../../../util/focus/dpad_keys.dart';
import '../../../../../util/platform_detection.dart';
import '../../../../widgets/navigation_layout.dart';
import '../../detail_episode_images.dart';
import '../shared/nouveau_media_rail_card.dart';
import '../shared/nouveau_spacing.dart';

Duration _chapterPosition(Map<String, dynamic> chapter) {
  final ticks = chapter['StartPositionTicks'];

  if (ticks is! num) {
    return Duration.zero;
  }

  return Duration(microseconds: ticks.toInt() ~/ 10);
}

class NouveauChaptersSection extends StatefulWidget {
  final AggregatedItem item;
  final ImageApi imageApi;
  final ValueChanged<Duration> onPlayFromChapter;
  final bool Function()? onNavigateUp;
  final bool Function()? onNavigateDown;

  const NouveauChaptersSection({
    super.key,
    required this.item,
    required this.imageApi,
    required this.onPlayFromChapter,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  @override
  State<NouveauChaptersSection> createState() =>
      NouveauChaptersSectionState();
}

class NouveauChaptersSectionState extends State<NouveauChaptersSection> {
  final Map<int, FocusNode> _focusNodes = {};
  int? _lastFocusedIndex;

  FocusNode _nodeFor(int index) => _focusNodes.putIfAbsent(index, () {
    final node = FocusNode(debugLabel: 'chapters:$index');
    node.addListener(() {
      if (node.hasFocus) {
        _lastFocusedIndex = index;
      }
    });
    return node;
  });

  bool get canFocusTop => mounted && widget.item.chapters.isNotEmpty;

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

  bool focusTop() {
    if (!canFocusTop) {
      return false;
    }

    final index = (_lastFocusedIndex ?? 0).clamp(
      0,
      widget.item.chapters.length - 1,
    );
    _nodeFor(index).requestFocus();

    return true;
  }

  bool focusBottom() => focusTop();

  bool get _navbarIsLeft =>
      GetIt.instance<UserPreferences>().get(UserPreferences.navbarPosition) ==
      NavbarPosition.left;

  void _handleLeftEdge() {
    NavigationLayout.focusNavbarNotifier.value?.call();
  }

  _ChaptersLayout _layoutFor(BuildContext context, double availableWidth) {
    final compact = _isCompactMobile(context);

    final double cardWidth;
    final double cardGap;
    if (compact) {
      final metrics = NouveauSpacing.compactChapters;
      cardWidth = metrics.itemWidth(availableWidth);
      cardGap = metrics.gap;
    } else {
      cardWidth = NouveauMediaRailMetrics.cardWidth(availableWidth);
      cardGap = NouveauMediaRailMetrics.itemGap;
    }

    final artworkHeight = NouveauMediaRailMetrics.artworkHeight(cardWidth);
    final itemsPerLine = ((availableWidth + cardGap) / (cardWidth + cardGap))
        .floor()
        .clamp(1, 1000);

    return _ChaptersLayout(
      cardWidth: cardWidth,
      cardGap: cardGap,
      artworkHeight: artworkHeight,
      compact: compact,
      itemsPerLine: itemsPerLine,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.item.chapters;

    if (chapters.isEmpty) {
      return const SizedBox.shrink();
    }

    final useSeriesThumbs = GetIt.instance<UserPreferences>().get(
      UserPreferences.detailUseSeriesThumbnails,
    );

    final l10n = AppLocalizations.of(context);

    final textTheme = Theme.of(context).textTheme;

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
              l10n.chapters,
              style: layout.compact
                  ? textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    )
                  : textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),

            SizedBox(
              height: layout.compact
                  ? NouveauSpacing.mobileTitleToContent
                  : NouveauSpacing.titleToContent,
            ),

            _buildGrid(context, chapters, layout, l10n, useSeriesThumbs),
          ],
        );
      },
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<Map<String, dynamic>> chapters,
    _ChaptersLayout layout,
    AppLocalizations l10n,
    bool useSeriesThumbs,
  ) {
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
          if (!atLineEnd && i + 1 < chapters.length) {
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
          if (below < chapters.length) {
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
      spacing: layout.cardGap,
      runSpacing: layout.cardGap,
      children: [
        for (final (i, chapter) in chapters.indexed)
          Builder(
            builder: (context) {
              final position = _chapterPosition(chapter);
              final rawName = (chapter['Name'] as String?)?.trim();
              final name = rawName?.isNotEmpty == true
                  ? rawName!
                  : l10n.chapterNumber(i + 1);
              final imageUrl = _chapterImageUrl(
                context,
                chapter,
                i,
                layout.cardWidth,
                useSeriesThumbs,
              );
              final displayName = _cleanChapterDisplay(name, position);

              return Focus(
                focusNode: _nodeFor(i),
                onKeyEvent: keyHandler(i),
                child: Builder(
                  builder: (context) => NouveauMediaRailCard(
                    imageUrl: imageUrl,
                    title: displayName,
                    placeholderLabel: name,
                    width: layout.cardWidth,
                    artworkHeight: layout.artworkHeight,
                    isFocused: Focus.of(context).hasFocus,
                    onTap: () => widget.onPlayFromChapter(position),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  String? _chapterImageUrl(
    BuildContext context,
    Map<String, dynamic> chapter,
    int index,
    double cardWidth,
    bool useSeriesThumbs,
  ) {
    final maxWidth = (cardWidth * MediaQuery.devicePixelRatioOf(context))
        .ceil();

    if (useSeriesThumbs) {
      final seriesThumbnail = resolveSeriesLandscapeThumbnailUrl(
        widget.item,
        widget.imageApi,
        maxWidth: maxWidth,
      );

      if (seriesThumbnail != null && seriesThumbnail.isNotEmpty) {
        return seriesThumbnail;
      }
    }

    final imageTag = chapter['ImageTag'] as String?;

    if (imageTag == null || imageTag.isEmpty) {
      return null;
    }

    final chapterImage = widget.imageApi.getChapterImageUrl(
      widget.item.id,
      index: index,
      maxWidth: maxWidth,
      tag: imageTag,
    );

    return chapterImage.isEmpty ? null : chapterImage;
  }

  String _cleanChapterDisplay(String rawName, Duration position) {
    final duration = _formatDuration(position);

    final parts = rawName.split(RegExp(r'\s*-\s*'));

    final uniqueParts = <String>[];

    for (final part in parts) {
      final normalized = _normalizeTimeString(part);

      if (normalized.isNotEmpty && !uniqueParts.contains(normalized)) {
        uniqueParts.add(normalized);
      }
    }

    if (uniqueParts.isNotEmpty &&
        uniqueParts.last == _normalizeTimeString(duration)) {
      uniqueParts.removeLast();
    }

    return uniqueParts.isEmpty
        ? duration
        : '${uniqueParts.join(' - ')} - $duration';
  }

  String _normalizeTimeString(String value) {
    final parts = value.trim().split(':');

    if (parts.length == 2 && int.tryParse(parts[0]) != null) {
      return '${int.parse(parts[0])}:${parts[1]}';
    }

    if (parts.length == 3 &&
        int.tryParse(parts[0]) != null &&
        int.tryParse(parts[1]) != null) {
      final hours = int.parse(parts[0]);

      final minutes = int.parse(parts[1]);

      return hours == 0
          ? '$minutes:${parts[2]}'
          : '$hours:${minutes.toString().padLeft(2, '0')}:${parts[2]}';
    }

    return value.trim();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;

    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');

    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }

    return '${duration.inMinutes}:$seconds';
  }
}

class _ChaptersLayout {
  final double cardWidth;
  final double cardGap;
  final double artworkHeight;
  final bool compact;
  final int itemsPerLine;

  const _ChaptersLayout({
    required this.cardWidth,
    required this.cardGap,
    required this.artworkHeight,
    required this.compact,
    required this.itemsPerLine,
  });
}

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../../preference/preference_constants.dart';
import '../../../../../preference/user_preferences.dart';
import '../../../../../util/focus/dpad_keys.dart';
import '../../../../../util/platform_detection.dart';
import '../../../../widgets/focus/focusable_wrapper.dart';
import '../../../../widgets/navigation_layout.dart';
import '../shared/nouveau_spacing.dart';
import 'nouveau_people_card.dart';

// 26.10, Sid ("la distribution, c'est aussi trop petit, on voit rien du
// tout. Reprendre celui de moderne, là on voit bien" + "pas de scroll
// nulle part") - même traitement que NouveauDiscoveryRail juste à côté :
// LockedFocusRow (défilement horizontal, nombre de cartes forcé à tenir
// dans la largeur - _fullVisibleCards=10, donnant des avatars minuscules
// sur un grand écran) remplacé par une vraie grille Wrap, avec une largeur
// de carte FIXE proche de celle de Modern (DetailCastRow côté
// item_detail_screen.dart : ~100px de carte / ~90px d'avatar), pas
// recalculée pour forcer un compte fixe de colonnes.
class NouveauPeopleSection extends StatefulWidget {
  final List<Map<String, dynamic>> actors;
  final List<Map<String, dynamic>> directors;
  final List<Map<String, dynamic>> writers;
  final ImageApi imageApi;
  final String? serverId;
  final bool Function()? onNavigateUp;
  final bool Function()? onNavigateDown;

  const NouveauPeopleSection({
    super.key,
    required this.actors,
    required this.directors,
    required this.writers,
    required this.imageApi,
    required this.serverId,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  @override
  State<NouveauPeopleSection> createState() => NouveauPeopleSectionState();
}

class NouveauPeopleSectionState extends State<NouveauPeopleSection> {
  // Cible proche de DetailCastRow (Modern) - voir item_detail_screen.dart,
  // cardWidth ~100 / avatarRadius ~45 (donc ~90 de diamètre) sur desktop.
  static const double _targetCardWidth = 108.0;
  static const double _minCardWidth = 92.0;
  static const double _maxCardWidth = 128.0;
  static const double _avatarWidthFactor = 0.80;

  final Map<int, FocusNode> _focusNodes = {};

  // 30.10, Sid ("distribution, on garde comme c'est maintenant mais à
  // dérouler comme tu as mis") - repliée par défaut, comme la maquette ;
  // le contenu (grille) reste identique, seule sa visibilité change.
  bool _expanded = false;

  final FocusNode _headerFocusNode = FocusNode(debugLabel: 'people:header');

  FocusNode _nodeFor(int index) =>
      _focusNodes.putIfAbsent(index, () => FocusNode(debugLabel: 'people:$index'));

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _headerFocusNode.dispose();
    super.dispose();
  }

  bool _isCompactMobile(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return !PlatformDetection.isTV && size.shortestSide < 600;
  }

  bool get canFocusTop =>
      mounted &&
      _focusNodes.isNotEmpty &&
      (widget.actors.isNotEmpty ||
          widget.directors.isNotEmpty ||
          widget.writers.isNotEmpty);

  bool get _navbarIsLeft =>
      GetIt.instance<UserPreferences>().get(UserPreferences.navbarPosition) ==
      NavbarPosition.left;

  bool focusTop() {
    if (!canFocusTop) {
      return false;
    }
    _headerFocusNode.requestFocus();
    return true;
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  bool _focusFirstPersonOrPassThrough() {
    if (!_expanded) {
      return widget.onNavigateDown?.call() ?? false;
    }
    _nodeFor(0).requestFocus();
    return true;
  }

  List<Map<String, dynamic>> _mergeCreators(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final merged = <String, _CreatorEntry>{};

    void addPeople(
      List<Map<String, dynamic>> people, {
      required bool isDirector,
      required bool isWriter,
    }) {
      for (final person in people) {
        final id = person['Id']?.toString().trim() ?? '';
        final name = person['Name']?.toString().trim() ?? '';

        if (id.isEmpty && name.isEmpty) {
          continue;
        }

        final key = id.isNotEmpty ? 'id:$id' : 'name:${name.toLowerCase()}';

        final entry = merged.putIfAbsent(
          key,
          () => _CreatorEntry(person: person),
        );

        if (isDirector) {
          entry.isDirector = true;
        }

        if (isWriter) {
          entry.isWriter = true;
        }
      }
    }

    addPeople(widget.directors, isDirector: true, isWriter: false);
    addPeople(widget.writers, isDirector: false, isWriter: true);

    return [
      for (final entry in merged.values)
        {
          ...entry.person,
          'Role': [
            if (entry.isDirector) l10n.director,
            if (entry.isWriter) l10n.writer,
          ].join(', '),
        },
    ];
  }

  String _title(
    BuildContext context, {
    required bool hasCast,
    required bool hasCreators,
  }) {
    final l10n = AppLocalizations.of(context);

    if (hasCast && hasCreators) {
      return l10n.castAndCrew;
    }
    if (hasCast) {
      return l10n.castMembers;
    }
    return l10n.crewSection;
  }

  _PeopleLayout _layoutFor(BuildContext context, double availableWidth) {
    final compact = _isCompactMobile(context);
    final textScaler = MediaQuery.textScalerOf(context);

    if (compact) {
      final metrics = NouveauSpacing.compactPeople;
      final cardWidth = metrics.itemWidth(availableWidth);
      final avatarSize =
          (cardWidth * NouveauSpacing.compactPeopleAvatarWidthFactor).clamp(
            NouveauSpacing.compactPeopleMinAvatarSize,
            NouveauSpacing.compactPeopleMaxAvatarSize,
          );
      final nameHeight = textScaler.scale(38).clamp(38.0, 56.0);
      final roleHeight = textScaler.scale(32).clamp(32.0, 48.0);
      final cardHeight = avatarSize + 12 + nameHeight + 4 + roleHeight;
      final itemsPerLine = ((availableWidth + metrics.gap) / (cardWidth + metrics.gap))
          .floor()
          .clamp(1, 1000);

      return _PeopleLayout(
        cardWidth: cardWidth,
        cardSpacing: metrics.gap,
        avatarSize: avatarSize,
        cardHeight: cardHeight,
        compact: true,
        itemsPerLine: itemsPerLine,
      );
    }

    final itemGap = PlatformDetection.isTV
        ? NouveauSpacing.tvRailItemGap
        : NouveauSpacing.railItemGap;
    final avatarWidthFactor = PlatformDetection.isTV
        ? NouveauSpacing.tvPeopleAvatarWidthFactor
        : _avatarWidthFactor;
    final cardWidth = _targetCardWidth.clamp(_minCardWidth, _maxCardWidth);
    final avatarSize = cardWidth * avatarWidthFactor;
    final nameHeight = textScaler.scale(34).clamp(34.0, 54.0);
    final roleHeight = textScaler.scale(30).clamp(30.0, 48.0);
    final cardHeight = avatarSize + 12 + nameHeight + roleHeight;
    final itemsPerLine = ((availableWidth + itemGap) / (cardWidth + itemGap))
        .floor()
        .clamp(1, 1000);

    return _PeopleLayout(
      cardWidth: cardWidth,
      cardSpacing: itemGap,
      avatarSize: avatarSize,
      cardHeight: cardHeight,
      compact: false,
      itemsPerLine: itemsPerLine,
    );
  }

  @override
  Widget build(BuildContext context) {
    final creators = _mergeCreators(context);

    final hasCast = widget.actors.isNotEmpty;
    final hasCreators = creators.isNotEmpty;

    if (!hasCast && !hasCreators) {
      return const SizedBox.shrink();
    }

    final people = [...widget.actors, ...creators];
    final title = _title(context, hasCast: hasCast, hasCreators: hasCreators);
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final layout = _layoutFor(context, availableWidth);

        final titleStyle = layout.compact
            ? textTheme.titleLarge?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.1,
              )
            : textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FocusableWrapper(
              focusNode: _headerFocusNode,
              onSelect: _toggleExpanded,
              onNavigateUp: widget.onNavigateUp,
              onNavigateDown: _focusFirstPersonOrPassThrough,
              borderRadius: 10,
              disableScale: true,
              child: GestureDetector(
                onTap: _toggleExpanded,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: titleStyle),
                    const SizedBox(width: 8),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: titleStyle?.color ?? Colors.white,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              SizedBox(
                height: layout.compact
                    ? NouveauSpacing.mobileTitleToContent
                    : NouveauSpacing.titleToContent,
              ),
              _buildGrid(context, people, layout),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<Map<String, dynamic>> people,
    _PeopleLayout layout,
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
              NavigationLayout.focusNavbarNotifier.value?.call();
            }
            return KeyEventResult.handled;
          }
          _nodeFor(i - 1).requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey.isRightKey) {
          final atLineEnd = i % layout.itemsPerLine == layout.itemsPerLine - 1;
          if (!atLineEnd && i + 1 < people.length) {
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
          _headerFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey.isDownKey) {
          final below = i + layout.itemsPerLine;
          if (below < people.length) {
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
        for (final (i, person) in people.indexed)
          Focus(
            focusNode: _nodeFor(i),
            onKeyEvent: keyHandler(i),
            child: Builder(
              builder: (context) {
                final isFocused = Focus.of(context).hasFocus;
                return GestureDetector(
                  onTap: () => NouveauPeopleCard.openPerson(
                    context,
                    person,
                    serverId: widget.serverId,
                  ),
                  child: NouveauPeopleCard(
                    person: person,
                    imageApi: widget.imageApi,
                    serverId: widget.serverId,
                    width: layout.cardWidth,
                    avatarSize: layout.avatarSize,
                    isFocused: isFocused,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _CreatorEntry {
  final Map<String, dynamic> person;

  bool isDirector = false;
  bool isWriter = false;

  _CreatorEntry({required this.person});
}

class _PeopleLayout {
  final double cardWidth;
  final double cardSpacing;
  final double avatarSize;
  final double cardHeight;
  final bool compact;
  final int itemsPerLine;

  const _PeopleLayout({
    required this.cardWidth,
    required this.cardSpacing,
    required this.avatarSize,
    required this.cardHeight,
    required this.compact,
    required this.itemsPerLine,
  });
}

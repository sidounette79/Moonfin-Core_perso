import 'package:flutter/material.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../util/focus/dpad_keys.dart';
import '../../../../../util/platform_detection.dart';
import '../../../../widgets/offline_aware_image.dart';

/// 30.10, Sid ("j'ai bien le reprendre mais pas une miniature de l'épisode
/// qui irait avec") - a real thumbnail + title + overview for the episode
/// "Reprendre" is about to launch, shown above the Audio/Sous-titres bar
/// and the action buttons. Unlike [NouveauResumeProgressBar] (same
/// folder), which only renders once there's a real in-progress playback
/// position, this always shows for any resolvable next-up/resume episode -
/// that's the actual gap she flagged: a never-started episode had no
/// visual at all before this.
///
/// 30.10, Sid again ("ça fait doublon... c'est le format vidéo") - no
/// technical badges (resolution/codec/size) here on purpose, even though
/// an earlier version of this card had them: NouveauTrackInfoBar's own
/// "Vidéo" field right below already covers that, and she wants it to
/// stay there specifically ("j'en ai besoin sous la barre") rather than
/// repeated here too.
///
/// 30.10, Sid ("est-ce que quand cliquant sur la miniature, ça peut lancer
/// la lecture ?") - the thumbnail itself is tappable and plays [episode]
/// (the one actually shown - the focused one in the grid if there is one,
/// the real "Reprendre" episode otherwise).
///
/// 30.10, Sid again ("on ne peut pas accéder à la miniature... ça fait pas
/// super joli") - on TV this card used to have no FocusNode at all, so the
/// D-pad simply couldn't reach it; [focusNode] makes it a real stop in the
/// chain (Select/Enter plays, same as a tap) when the caller wires one in.
class NouveauEpisodePreviewCard extends StatelessWidget {
  final AggregatedItem episode;
  final String? imageUrl;
  final VoidCallback? onPlay;
  final FocusNode? focusNode;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowUp;

  const NouveauEpisodePreviewCard({
    super.key,
    required this.episode,
    required this.imageUrl,
    this.onPlay,
    this.focusNode,
    this.onArrowLeft,
    this.onArrowDown,
    this.onArrowUp,
  });

  String? _runtimeLabel() {
    final runtime = episode.runtime;
    if (runtime == null || runtime.inMilliseconds <= 0) return null;
    final minutes = runtime.inMinutes;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final rest = minutes % 60;
      return rest > 0 ? '${hours}h ${rest}m' : '${hours}h';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final season = episode.parentIndexNumber;
    final ep = episode.indexNumber;
    final heading = season != null && ep != null
        ? l10n.seasonEpisodeLabel(season, ep)
        : null;
    final runtimeLabel = _runtimeLabel();
    final overview = episode.overview?.trim();

    // 30.10, Sid ("sur TV ça bouffe tout l'écran, et c'est quand même une
    // 165 pouces") - sur mobile le Column parent est déjà étroit (largeur
    // du téléphone), mais côté Nouveau landscape/TV la colonne de contenu
    // suit une largeur d'écran bien plus généreuse, et rien ne plafonnait
    // la largeur de cette carte - elle s'étirait d'un bord à l'autre.
    final maxWidth = PlatformDetection.isTV ? 640.0 : double.infinity;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Focus(
            focusNode: focusNode,
            onKeyEvent: (node, event) {
              if (!event.isActionable) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key.isSelectKey) {
                if (onPlay == null) return KeyEventResult.ignored;
                onPlay!();
                return KeyEventResult.handled;
              }
              if (key.isLeftKey && onArrowLeft != null) {
                onArrowLeft!();
                return KeyEventResult.handled;
              }
              if (key.isDownKey && onArrowDown != null) {
                onArrowDown!();
                return KeyEventResult.handled;
              }
              if (key.isUpKey && onArrowUp != null) {
                onArrowUp!();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final hasFocus = Focus.of(context).hasFocus;
                return GestureDetector(
                  onTap: onPlay,
                  child: MouseRegion(
                    cursor: onPlay != null
                        ? SystemMouseCursors.click
                        : MouseCursor.defer,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: hasFocus
                              ? Colors.white
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              imageUrl != null
                                  ? OfflineAwareImage(
                                      imageUrl: imageUrl!,
                                      fit: BoxFit.cover,
                                    )
                                  : ColoredBox(
                                      color: Colors.white.withValues(alpha: 0.08),
                                    ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.55),
                                    ],
                                    stops: const [0.55, 1.0],
                                  ),
                                ),
                              ),
                              if (onPlay != null)
                                const Center(
                                  child: Icon(
                                    Icons.play_circle_fill,
                                    color: Colors.white,
                                    size: 54,
                                  ),
                                ),
                              if (heading != null)
                                Positioned(
                                  top: 10,
                                  left: 10,
                                  child: _badge(heading, bold: true),
                                ),
                              if (runtimeLabel != null)
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: _badge(runtimeLabel),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 9),
          Text(
            episode.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (overview != null && overview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              overview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _badge(String text, {bool bold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          letterSpacing: bold ? 0.04 : 0,
        ),
      ),
    );
  }
}

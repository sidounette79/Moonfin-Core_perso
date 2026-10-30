import 'package:flutter/material.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../widgets/offline_aware_image.dart';
import '../../item_detail_screen.dart' show technicalDetailsFor;

/// 30.10, Sid ("j'ai bien le reprendre mais pas une miniature de l'épisode
/// qui irait avec") - a real thumbnail + title + overview + technical
/// badges for the episode "Reprendre" is about to launch, shown above the
/// Audio/Sous-titres bar and the action buttons. Unlike
/// [NouveauResumeProgressBar] (same folder), which only renders once
/// there's a real in-progress playback position, this always shows for any
/// resolvable next-up/resume episode - that's the actual gap she flagged:
/// a never-started episode had no visual at all before this.
///
/// Deliberately not focusable - the existing "Reprendre" button already
/// handles play, and wiring a new element into the D-pad chain here would
/// touch the same fragile focus wiring responsible for several bugs this
/// session. Purely informative.
class NouveauEpisodePreviewCard extends StatelessWidget {
  final AggregatedItem episode;
  final String? imageUrl;
  final Map<String, dynamic>? selectedMediaSource;

  const NouveauEpisodePreviewCard({
    super.key,
    required this.episode,
    required this.imageUrl,
    this.selectedMediaSource,
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
    final tech = technicalDetailsFor(episode, selectedMediaSource);
    final hasTechBadges = tech.badges.isNotEmpty || tech.formattedSize != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageUrl != null
                      ? OfflineAwareImage(imageUrl: imageUrl!, fit: BoxFit.cover)
                      : ColoredBox(color: Colors.white.withValues(alpha: 0.08)),
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
                  if (heading != null)
                    Positioned(top: 10, left: 10, child: _badge(heading, bold: true)),
                  if (runtimeLabel != null)
                    Positioned(top: 10, right: 10, child: _badge(runtimeLabel)),
                ],
              ),
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
          if (hasTechBadges) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final badge in tech.badges) _techPill(badge),
                if (tech.formattedSize != null) _techPill(tech.formattedSize!),
              ],
            ),
          ],
        ],
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

  Widget _techPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

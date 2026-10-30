import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../../l10n/app_localizations.dart';

/// 26.10, Sid (captures d'écran Emby côte à côte avec Nouveau/Modern) :
/// "J'aime la petite barre de progression qui n'existe pas dans nouveau. A
/// creer à l'identique de emby avec saison, épisode, titre, la barre en
/// bleu pour la progression et le temps restant." - contrairement au liseré
/// de 2px déjà peint sur le bouton "Reprendre" lui-même (voir
/// _NouveauPrimaryButton), ceci est un bloc à part entière, juste en
/// dessous de la rangée de boutons, même position qu'Emby.
///
/// 30.10, Sid ("Ça fait doublon, mais surtout le premier est tronqué") -
/// une fois ce widget déplacé juste sous NouveauEpisodePreviewCard (voir
/// item_detail_screen.dart), qui affiche déjà le S/E et le titre de
/// l'épisode dans sa propre vignette, son propre titre "S1 E2 - Nom" ici
/// devenait un doublon redondant - retiré, seules la barre et le temps
/// restant subsistent. Seul appelant (item_detail_screen.dart), donc
/// aucun autre contexte ne dépend de ce titre.
class NouveauResumeProgressBar extends StatelessWidget {
  /// L'item dont la progression est affichée - l'épisode en cours pour une
  /// série (voir viewModel.nextUp côté appelant), l'item lui-même pour un
  /// film/épisode direct.
  final AggregatedItem resumeItem;

  const NouveauResumeProgressBar({super.key, required this.resumeItem});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final runtime = resumeItem.runtime;
    final position = resumeItem.playbackPosition ?? Duration.zero;

    if (runtime == null ||
        runtime.inMilliseconds <= 0 ||
        position.inMilliseconds <= 0 ||
        position >= runtime) {
      return const SizedBox.shrink();
    }

    final progress = (position.inMilliseconds / runtime.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();

    final remaining = runtime - position;
    final remainingMinutes = (remaining.inSeconds / 60).ceil();
    final String remainingLabel;
    if (remainingMinutes >= 60) {
      final hours = remainingMinutes ~/ 60;
      final minutes = remainingMinutes % 60;
      final formatted = minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
      remainingLabel = l10n.timeRemaining(formatted);
    } else {
      remainingLabel = l10n.timeRemaining('${remainingMinutes.clamp(1, 999)}m');
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.22),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColorScheme.accent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                remainingLabel,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

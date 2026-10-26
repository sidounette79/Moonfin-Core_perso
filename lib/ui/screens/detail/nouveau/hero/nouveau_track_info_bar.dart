import 'package:flutter/material.dart';

/// 26.10, Sid (captures Emby) : "Dans emby, je peux facilement changer les
/// sous-titres ou l'audio. Il faudrait que ça soit lié au reprendre. Le
/// audio devient déroulant aussi quand il existe" puis "Mais ça reste
/// derrière un bouton, faut le sortir de la barre des boutons" - ligne
/// Vidéo/Audio/Sous-titres juste au-dessus de "Reprendre", comme Emby.
/// Vidéo = toujours du texte simple (une seule piste vidéo). Audio/
/// Sous-titres = texte simple s'il n'y a qu'une seule option, ou une
/// puce "déroulante" (nom + chevron) qui ouvre le vrai sélecteur déjà
/// existant (TrackSelectorDialog, voir _showAudioSelector/
/// _openSubtitleSelector dans item_detail_screen.dart) dès qu'il y a un
/// vrai choix à faire - jamais de menu déroulant natif réimplémenté ici,
/// juste l'apparence, pour rester compatible D-pad TV comme le reste de
/// l'app.
class NouveauTrackInfoBar extends StatelessWidget {
  final String videoLabel;
  final String audioTitle;
  final String? audioLabel;
  final VoidCallback? onAudioTap;
  final String subtitleTitle;
  final String? subtitleLabel;
  final VoidCallback? onSubtitleTap;

  const NouveauTrackInfoBar({
    super.key,
    required this.videoLabel,
    required this.audioTitle,
    this.audioLabel,
    this.onAudioTap,
    required this.subtitleTitle,
    this.subtitleLabel,
    this.onSubtitleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _InfoField(title: 'Vidéo', value: videoLabel),
          if (audioLabel != null)
            _InfoField(
              title: audioTitle,
              value: audioLabel!,
              onTap: onAudioTap,
            ),
          if (subtitleLabel != null)
            _InfoField(
              title: subtitleTitle,
              value: subtitleLabel!,
              onTap: onSubtitleTap,
            ),
        ],
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback? onTap;

  const _InfoField({required this.title, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.55),
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = const TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: titleStyle),
        const SizedBox(width: 6),
        if (onTap == null)
          Text(value, style: valueStyle)
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: valueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more, color: Colors.white, size: 16),
              ],
            ),
          ),
      ],
    );

    if (onTap == null) {
      return content;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: content,
    );
  }
}

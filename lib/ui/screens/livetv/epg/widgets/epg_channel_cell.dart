import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../widgets/bounded_network_image.dart';
import '../../../../widgets/marquee_text.dart';

/// 02.10, Sid: "reprendre le visuel clubtivi à l'identique" for the IPTV
/// screen specifically - but this cell is ALSO used by Emby's own native
/// Live TV guide (live_tv_guide_screen.dart), which should keep its own
/// Moonfin look untouched. Rather than hardcode clubTivi's literal colors
/// into this shared widget (which would silently reskin the Emby screen
/// too), an optional override bundle: null everywhere except the IPTV
/// screen, which is the only caller that constructs one.
class EpgCellStyleOverride {
  final Color restingBackground;
  final Color focusedBackground;
  final Color focusBorderColor;
  final Color nameColor;
  final Color logoFallbackBackground;

  /// 03.10, Sid: "police du guide trop grande" - multiplie toutes les
  /// tailles de police de la cellule (nom de chaîne + titre/horaire du
  /// programme). Null = taille normale (Emby, qui ne passe jamais
  /// d'override), jamais touché directement ici pour ne pas reskiner
  /// l'écran Emby natif au passage.
  final double? fontScale;

  const EpgCellStyleOverride({
    required this.restingBackground,
    required this.focusedBackground,
    required this.focusBorderColor,
    required this.nameColor,
    required this.logoFallbackBackground,
    this.fontScale,
  });
}

/// Channel identity cell for the guide rail: logo pinned left, with the accent
/// number chip and the channel name right-justified against the cell's trailing
/// edge. The cell itself provides the contrast surface for the bare logo. Pure
/// presentation. The host owns focus + key handling and
/// passes [focused]. Idiom-aware surface (glass-tinted on Apple, accent tint on
/// Material).
class EpgChannelCell extends StatelessWidget {
  final String? logoUrl;
  final String name;
  final String? number;
  final bool focused;
  final bool apple;

  /// Marks the channel as a favourite with a red heart beside the number.
  final bool isFavorite;

  /// 02.10, Sid: "je ne sais jamais vraiment où est situé mon sélecteur" -
  /// root cause was this cell using the SAME [focused] treatment for "this
  /// is the channel currently playing" and "this is where the D-pad cursor
  /// is", so once focus moved away from the playing channel, its row kept
  /// looking focused and the real cursor position had no visible tell.
  /// Playing now gets its own small, quiet indicator instead of sharing
  /// the focus ring/background.
  final bool playing;

  /// See [EpgCellStyleOverride] - null everywhere except the clubTivi-style
  /// IPTV screen.
  final EpgCellStyleOverride? styleOverride;

  /// Above this the rail is the one a television lays out, and the cell steps
  /// up to a face that carries at ten feet. Below it the rail belongs to a
  /// window being read at arm's length, where the larger face would only crowd
  /// the call sign out.
  static const double _tenFootRailWidth = 180;

  /// The number is what a viewer navigates by, so it outsizes the call sign.
  static double _numberSize(double width) =>
      width >= _tenFootRailWidth ? 20 : 13;

  static double _nameSize(double width, double fontScale) =>
      (width >= _tenFootRailWidth ? 18 : 12) * fontScale;

  /// Icons set in a line of text take this share of that line's face, so they
  /// keep their weight beside it at any interface size.
  static const double _inlineIconShare = 0.8;

  /// The share of the cell the logo takes, and the bounds it keeps whatever
  /// the rail is given. A share rather than a fixed width because the rail is
  /// itself a share of the canvas, and a logo sized for the roomy one leaves
  /// the call sign nowhere to go on a narrow one.
  static const double _logoWidthFactor = 0.36;
  static const double _logoMinWidth = 40;
  static const double _logoMaxWidth = 66;
  static const double _logoGap = 6;
  static const Color _restingCellColor = Color(0xEF353940);

  const EpgChannelCell({
    super.key,
    required this.logoUrl,
    required this.name,
    required this.number,
    required this.focused,
    required this.apple,
    this.isFavorite = false,
    this.playing = false,
    this.styleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final override = styleOverride;
    final accent = override?.focusBorderColor ?? AppColorScheme.accent;
    final radius = apple ? 14.0 : 10.0;
    final Color bg;
    if (focused) {
      bg = override?.focusedBackground ??
          (apple
              ? Colors.white.withValues(alpha: 0.16)
              : accent.withValues(alpha: 0.16));
    } else {
      // This is the cell surface, not a logo tile. The muted slate is bright
      // enough for black station marks while keeping white rail text legible.
      bg = override?.restingBackground ?? _restingCellColor;
    }

    // Sized from the rail rather than left on the body token, which is meant
    // for reading at arm's length and lands under the ten foot floor once a
    // television scales the canvas down onto the panel.
    final fontScale = override?.fontScale ?? 1.0;
    TextStyle? nameStyleFor(double width) => textTheme.bodySmall?.copyWith(
      fontSize: _nameSize(width, fontScale),
      fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
      color: override?.nameColor ?? AppColorScheme.onSurface,
    );

    Widget bodyFor(double width) {
      final nameStyle = nameStyleFor(width);
      final chip = number == null
          ? null
          : _numberChip(number!, accent, _numberSize(width));
      final hasTopRow = chip != null || isFavorite || playing;
      return Row(
        children: [
          _logo((width * _logoWidthFactor).clamp(_logoMinWidth, _logoMaxWidth)),
          const SizedBox(width: _logoGap),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasTopRow) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // 02.10, Sid: the "playing" tell used to be the SAME
                      // accent background/border as D-pad focus
                      // (EpgChannelCell's own `focused` flag covered both),
                      // so once the cursor moved away from the playing
                      // channel its row still looked exactly like the
                      // focused one. This small dot is the only thing that
                      // marks "currently playing" now - the border/bg
                      // above is focus-only.
                      if (playing) ...[
                        Icon(
                          Icons.circle,
                          size:
                              scaler.scale(_numberSize(width)) *
                              _inlineIconShare *
                              0.6,
                          color: AppColors.green500,
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (isFavorite) ...[
                        Icon(
                          Icons.favorite,
                          size:
                              scaler.scale(_numberSize(width)) *
                              _inlineIconShare,
                          color: AppColors.red500,
                        ),
                        const SizedBox(width: 4),
                      ],
                      ?chip,
                    ],
                  ),
                  const SizedBox(height: 3),
                ],
                focused
                    ? SizedBox(
                        width: double.infinity,
                        child: MarqueeText(
                          text: name,
                          style: nameStyle ?? const TextStyle(),
                          showDotSeparator: false,
                          textAlign: TextAlign.right,
                        ),
                      )
                    : Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: nameStyle,
                      ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.circular(radius),
        // Always reserve the border so focus doesn't change the cell height.
        border: Border.all(
          color: focused ? accent.withValues(alpha: 0.7) : Colors.transparent,
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => bodyFor(constraints.maxWidth),
      ),
    );
  }

  /// The image viewport fills the cell's available height. The cell surface
  /// behind it supplies the contrast, so logos don't get a second card.
  Widget _logo(double width) => SizedBox(
    width: width,
    height: double.infinity,
    child: (logoUrl != null && logoUrl!.isNotEmpty)
        ? BoundedNetworkImage(
            imageUrl: logoUrl!,
            fit: BoxFit.contain,
            fadeInDuration: Duration.zero,
            maxWidth: 256,
            errorBuilder: (context, url, error) => _fallback(),
          )
        : _fallback(),
  );

  Widget _fallback() {
    final bg = styleOverride?.logoFallbackBackground;
    final icon = Icon(
      Icons.tv,
      size: 16,
      color: bg != null
          ? Colors.white24
          : AppColorScheme.onSurface.withValues(alpha: 0.5),
    );
    return bg == null ? icon : ColoredBox(color: bg, child: icon);
  }

  Widget _numberChip(String number, Color accent, double size) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: focused
          ? accent
          : AppColorScheme.onSurface.withValues(alpha: 0.12),
      borderRadius: AppRadius.circular(7),
    ),
    child: Text(
      number,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: focused
            ? const Color(0xFF062430)
            : AppColorScheme.onSurface.withValues(alpha: 0.85),
      ),
    ),
  );
}

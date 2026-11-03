import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';
import '../adaptive/sf_symbol.dart';

/// The delay stepper under a track picker. [autoOffset] is a correction the
/// backend applied on its own and only shows when there is one. It is
/// read only and rides beside the value the user sets, so Reset leaves it.
class DelayFooter extends StatefulWidget {
  const DelayFooter({
    super.key,
    required this.initialDelay,
    required this.label,
    this.minDelay,
    this.maxDelay,
    this.autoOffset = 0.0,
    this.autoOffsetStream,
    required this.onDelayChanged,
    required this.formatDelay,
  });

  final double initialDelay;
  final String label;
  final double? minDelay;
  final double? maxDelay;
  final double autoOffset;
  final Stream<double>? autoOffsetStream;
  final void Function(double delay) onDelayChanged;
  final String Function(double seconds) formatDelay;

  @override
  State<DelayFooter> createState() => _DelayFooterState();
}

class _DelayFooterState extends State<DelayFooter> {
  // See the Slider's own build-site comment - deliberately much tighter
  // than widget.minDelay/maxDelay (which can be +/-300s), so dragging
  // stays precise for the typical small drift. The stepper below reaches
  // anything beyond this, audio delay included (its own real range is
  // +/-2s, well inside this anyway).
  static const double _sliderRangeSeconds = 15.0;

  late double _delay;
  late double _autoOffset;
  StreamSubscription<double>? _autoOffsetSubscription;

  @override
  void initState() {
    super.initState();
    _delay = widget.initialDelay;
    _autoOffset = widget.autoOffset;
    _autoOffsetSubscription = widget.autoOffsetStream?.listen((offset) {
      if (!mounted || offset == _autoOffset) return;
      setState(() => _autoOffset = offset);
    });
  }

  @override
  void dispose() {
    _autoOffsetSubscription?.cancel();
    super.dispose();
  }

  void _adjust(double delta) {
    var next = ((_delay + delta) * 10).roundToDouble() / 10;
    final min = widget.minDelay;
    final max = widget.maxDelay;
    if (min != null && next < min) next = min;
    if (max != null && next > max) next = max;
    if (next == _delay) return;
    setState(() => _delay = next);
    widget.onDelayChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: AppTypography.fontSizeSm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                widget.formatDelay(_delay),
                style: TextStyle(
                  color: AppColorScheme.accent,
                  fontSize: AppTypography.fontSizeSm,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (_autoOffset != 0.0) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                l10n.subtitleDelayAuto(widget.formatDelay(_autoOffset)),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: AppTypography.fontSizeXs,
                ),
              ),
            ),
          ],
          // 03.11, Sid ("dans emby j'arrive super bien à caler avec la
          // barre... carba TV je tombe jamais bien dessus") - a coarse
          // +/-100ms-per-tap stepper alone made fine positioning tedious
          // for small drifts. A draggable Slider gives the same
          // fast-then-fine feel as Emby's own control, BUT mapping it to
          // this widget's full min/max (+/-300s for subtitles on Media3,
          // widened 30.10 for one real file that drifted that far) would
          // make dragging LESS precise than the stepper, not more - ~2s
          // per pixel over a typical slider width. Real-world subtitle
          // drift is almost always a few seconds at most; the 5-minute
          // case is the rare exception the stepper already exists to
          // reach. So the slider's own visual range is a fixed, much
          // tighter window (+/-_sliderRangeSeconds) independent of
          // widget.minDelay/maxDelay, which stay the stepper's real
          // clamp - landing near _sliderRangeSeconds/px precision, in
          // line with the stepper's own 100ms step. A delay already
          // outside that window (reached via the stepper) just shows the
          // thumb pinned at its edge; the value text above stays accurate
          // either way.
          if (widget.minDelay != null && widget.maxDelay != null) ...[
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColorScheme.accent,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: Colors.white24,
                trackHeight: 2,
              ),
              child: Builder(
                builder: (context) {
                  final sliderMin = math.max(
                    -_sliderRangeSeconds,
                    widget.minDelay!,
                  );
                  final sliderMax = math.min(
                    _sliderRangeSeconds,
                    widget.maxDelay!,
                  );
                  return Slider(
                    value: _delay.clamp(sliderMin, sliderMax),
                    min: sliderMin,
                    max: sliderMax,
                    onChanged: (v) {
                      final rounded = (v * 10).roundToDouble() / 10;
                      if (rounded == _delay) return;
                      setState(() => _delay = rounded);
                      widget.onDelayChanged(rounded);
                    },
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _adjust(-0.1),
                icon: const AdaptiveIcon(
                  Icons.remove_circle_outline,
                  color: Colors.white,
                  size: 28,
                ),
                tooltip: l10n.delayMinusMs(100),
              ),
              Text(
                l10n.delayMinusMs(100),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: AppTypography.fontSizeXs,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () {
                  setState(() => _delay = 0.0);
                  widget.onDelayChanged(0.0);
                },
                style: OutlinedButton.styleFrom(
                  side: ThemeRegistry.active.borders.chipBorder,
                ),
                child: Text(
                  l10n.reset,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Spacer(),
              Text(
                l10n.delayPlusMs(100),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: AppTypography.fontSizeXs,
                ),
              ),
              IconButton(
                onPressed: () => _adjust(0.1),
                icon: const AdaptiveIcon(
                  Icons.add_circle_outline,
                  color: Colors.white,
                  size: 28,
                ),
                tooltip: l10n.delayPlusMs(100),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

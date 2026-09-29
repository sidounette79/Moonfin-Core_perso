import 'package:flutter/material.dart';

import '../../../util/debug/nav_debug_log.dart';

/// 29.09: on-screen readout for [NavDebugLog], see that file for why this
/// exists. Bottom-left, non-focusable so it can't steal a real D-pad press
/// while it's watching them - it must never be part of the thing it's
/// debugging.
class NavDebugOverlay extends StatelessWidget {
  const NavDebugOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      bottom: 8,
      width: 520,
      child: ExcludeFocus(
        child: IgnorePointer(
          child: ValueListenableBuilder<List<String>>(
            valueListenable: NavDebugLog.lines,
            builder: (context, entries, _) {
              if (entries.isEmpty) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.greenAccent, width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in entries.reversed.take(14))
                      Text(
                        entry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

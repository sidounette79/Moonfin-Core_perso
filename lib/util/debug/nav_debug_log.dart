import 'package:flutter/foundation.dart';

/// 29.09, Sid: "mets une coccinelle si tu veux" - a temporary, in-app
/// diagnostic log for the "can't D-pad down past Continue Watching on TV"
/// bug. adb wasn't available, and static reading of
/// _onRowVerticalNavigation/_focusAdjacentRowItem in home_screen.dart found
/// nothing wrong in the shared, otherwise-working navigation mechanism, so
/// this captures what actually happens live on the TV screen instead of
/// guessing further. Remove (or hide behind NavDebugLog.enabled = false)
/// once the bug is found - this is not meant to ship long-term.
class NavDebugLog {
  NavDebugLog._();

  static const int _maxLines = 40;

  /// Flip to false to silence logging without ripping out every call site.
  static bool enabled = true;

  static final ValueNotifier<List<String>> lines = ValueNotifier<List<String>>(
    <String>[],
  );

  static void log(String message) {
    if (!enabled) return;
    final now = DateTime.now();
    final ts =
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${(now.millisecond ~/ 10).toString().padLeft(2, '0')}';
    final next = <String>[...lines.value, '$ts  $message'];
    if (next.length > _maxLines) {
      next.removeRange(0, next.length - _maxLines);
    }
    lines.value = next;
  }

  static void clear() => lines.value = <String>[];
}

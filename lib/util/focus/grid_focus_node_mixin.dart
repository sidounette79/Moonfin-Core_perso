import 'package:flutter/widgets.dart';

mixin GridFocusNodeMixin<T extends StatefulWidget> on State<T> {
  final Map<int, FocusNode> gridItemFocusNodes = {};
  final Map<int, VoidCallback> _gridItemListeners = {};
  int? lastFocusedGridIndex;
  int gridContentVersion = 0;
  int lastFocusedGridContentVersion = 0;

  FocusNode getGridItemFocusNode(int index, {String prefix = 'grid_item'}) {
    final existing = gridItemFocusNodes[index];
    if (existing != null) return existing;
    final node = FocusNode(debugLabel: '$prefix:$index');
    void listener() => trackGridItemFocus(index, node.hasFocus);
    node.addListener(listener);
    gridItemFocusNodes[index] = node;
    _gridItemListeners[index] = listener;
    return node;
  }

  void trackGridItemFocus(int index, bool hasFocus) {
    if (!hasFocus) return;
    lastFocusedGridIndex = index;
    lastFocusedGridContentVersion = gridContentVersion;
  }

  void cleanupGridFocusNodes(int currentCount) {
    final toRemove = gridItemFocusNodes.keys
        .where((i) => i >= currentCount)
        .toList(growable: false);
    for (final i in toRemove) {
      final node = gridItemFocusNodes.remove(i);
      final listener = _gridItemListeners.remove(i);
      if (node != null) {
        if (listener != null) node.removeListener(listener);
        node.dispose();
      }
    }
  }

  void disposeGridFocusNodes() {
    for (final entry in gridItemFocusNodes.entries) {
      final listener = _gridItemListeners[entry.key];
      if (listener != null) entry.value.removeListener(listener);
      entry.value.dispose();
    }
    gridItemFocusNodes.clear();
    _gridItemListeners.clear();
  }

  void restoreGridFocusIfNeeded() {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (lastFocusedGridContentVersion == gridContentVersion) return;
    final idx = lastFocusedGridIndex;
    if (idx == null) {
      // 30.09, Sid: "on arrive toujours sur la flèche (home en mode TV)
      // et pas sur le premier poster" - a fresh visit (nothing remembered
      // yet) otherwise leaves default Flutter focus traversal to land on
      // whatever's first in the tree, which is the toolbar's home/back
      // button, not the grid. Was fixed once for library_browse_screen.dart
      // only (27.09), gated to isTV - moved into the shared mixin so every
      // screen using it gets the same fix, and dropped the TV-only gate
      // since she confirmed the same thing happens on mobile too.
      final node = gridItemFocusNodes[0];
      if (node != null && node.canRequestFocus) {
        node.requestFocus();
      }
      return;
    }
    // 30.10, Sid ("le toggle vu, non vu... ça descend tout seul dans la
    // liste des series et je dois toujours retourner sur le toggle pour
    // recliquer"): a filter/sort toggle reclaims focus for itself right
    // after tapping (its own addPostFrameCallback, e.g. library_browse_
    // screen.dart's onPlayedFilterChanged), but the ViewModel change that
    // triggers it is itself async (setPlayedFilter awaits a prefs write
    // then a real reload) - so the data lands later, and this bumps
    // gridContentVersion and steals focus back to the grid a beat AFTER
    // the toggle already reclaimed it. Gated to the idx != null branch
    // only (a grid row was genuinely focused before, not the fresh-visit
    // case above) - there, a deliberate focus already sitting outside the
    // grid (the toggle, a search field, anything) is a choice this reload
    // has no business overriding. The fresh-visit case above still always
    // redirects, since the 30.09 fix depends on exactly that.
    final current = FocusManager.instance.primaryFocus;
    if (current != null &&
        current.hasFocus &&
        !gridItemFocusNodes.values.contains(current)) {
      lastFocusedGridContentVersion = gridContentVersion;
      return;
    }
    // The grid may have shrunk, so fall back to the last available row when the
    // remembered index no longer exists.
    var node = gridItemFocusNodes[idx];
    if (node == null && gridItemFocusNodes.isNotEmpty) {
      final maxIndex = gridItemFocusNodes.keys.reduce((a, b) => a > b ? a : b);
      node = gridItemFocusNodes[maxIndex];
    }
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
    }
    lastFocusedGridContentVersion = gridContentVersion;
  }
}

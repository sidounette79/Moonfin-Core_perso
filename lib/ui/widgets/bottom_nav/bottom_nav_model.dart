import '../../../preference/bottom_nav_tabs.dart';
import '../../navigation/destinations.dart';

// 06.11, Sid ("à la place de recherche, favoris etc... juste me donner le
// choix de mettre à la place"): library is a new kind, a specific pinned
// AggregatedLibrary.id rather than a fixed BottomNavTab - same bar cell
// shape (slot, label, icon), different source of truth.
enum BottomNavItemKind { home, tab, library, you }

/// One cell on the bar. [slot] is the cell's place among the offered items,
/// which is what the theme's navbar colour cycle is keyed on.
class BottomNavBarItem {
  final BottomNavItemKind kind;
  final BottomNavTab? tab;
  final String? libraryId;
  final int slot;

  const BottomNavBarItem._(this.kind, this.tab, this.libraryId, this.slot);

  const BottomNavBarItem.home() : this._(BottomNavItemKind.home, null, null, 0);

  const BottomNavBarItem.tab(BottomNavTab tab, int slot)
      : this._(BottomNavItemKind.tab, tab, null, slot);

  const BottomNavBarItem.library(String libraryId, int slot)
      : this._(BottomNavItemKind.library, null, libraryId, slot);

  const BottomNavBarItem.you(int slot)
      : this._(BottomNavItemKind.you, null, null, slot);

  String get id => switch (kind) {
        BottomNavItemKind.home => 'home',
        BottomNavItemKind.you => 'you',
        BottomNavItemKind.tab => tab!.name,
        BottomNavItemKind.library => 'lib:${libraryId!}',
      };

  @override
  bool operator ==(Object other) =>
      other is BottomNavBarItem &&
      other.kind == kind &&
      other.tab == tab &&
      other.libraryId == libraryId &&
      other.slot == slot;

  @override
  int get hashCode => Object.hash(kind, tab, libraryId, slot);

  @override
  String toString() => 'BottomNavBarItem($id, slot $slot)';
}

/// Home, the pinned tabs/libraries and You, with slots handed out over the
/// offered pins so one hidden for want of data doesn't recolour the ones
/// after it.
///
/// [withoutSearch] is for Split, which gives Search a button of its own.
/// [isAvailable] hides tab pins whose data isn't there, like Libraries
/// before any library has loaded. [availableLibraryIds] does the same for
/// a pinned library that no longer exists (deleted, or on a server no
/// longer reachable).
List<BottomNavBarItem> resolveBarItems(
  BottomNavTabGates gates,
  String rawPins, {
  bool withoutSearch = false,
  bool Function(BottomNavTab tab)? isAvailable,
  int maxPins = kDefaultMaxPinnedBottomNavTabs,
  Set<String> availableLibraryIds = const {},
}) {
  final pins = gates
      .resolvePins(rawPins, maxPins: maxPins)
      .where((item) => !(withoutSearch && item == const PinnedTab(BottomNavTab.search)))
      .toList();
  final items = <BottomNavBarItem>[const BottomNavBarItem.home()];
  for (var i = 0; i < pins.length; i++) {
    switch (pins[i]) {
      case PinnedTab(tab: final t):
        if (isAvailable != null && !isAvailable(t)) continue;
        items.add(BottomNavBarItem.tab(t, i + 1));
      case PinnedLibrary(libraryId: final id):
        if (!availableLibraryIds.contains(id)) continue;
        items.add(BottomNavBarItem.library(id, i + 1));
    }
  }
  items.add(BottomNavBarItem.you(pins.length + 1));
  return items;
}

/// Where each tab's own screens live, for lighting it up as the active one.
bool bottomNavTabMatchesRoute(BottomNavTab tab, String route) {
  bool under(String prefix) => route == prefix || route.startsWith('$prefix/');
  return switch (tab) {
    BottomNavTab.search => route == Destinations.search,
    BottomNavTab.libraries => under('/library') ||
        under('/library-view') ||
        under('/music') ||
        under('/books') ||
        under('/games'),
    BottomNavTab.favorites => route == Destinations.allFavorites,
    BottomNavTab.genres => route == Destinations.allGenres,
    BottomNavTab.liveTv => under(Destinations.liveTv),
    BottomNavTab.discover => under('/seerr'),
    BottomNavTab.folders =>
      route == Destinations.folderView || under('/folder'),
    // Opens a panel, not a route - never "active" by route the way a real
    // destination tab is.
    BottomNavTab.remoteControl => false,
  };
}

/// Whether [route] is this specific library's own screen - checked as a
/// whole path segment (`/library/42` or `/library/42/...`, not a prefix
/// match like `/library/420`) since library ids are server-assigned and
/// not guaranteed to never prefix one another.
bool bottomNavLibraryMatchesRoute(String libraryId, String route) {
  for (final base in ['/library/', '/library-view/', '/music/', '/books/']) {
    if (!route.startsWith(base)) continue;
    final rest = route.substring(base.length);
    final id = rest.split('/').first.split('?').first;
    if (id == libraryId) return true;
  }
  return false;
}

/// The index of the item to highlight, or null when the screen belongs to
/// none of them, like an item's detail page.
int? activeBarIndex(
  List<BottomNavBarItem> items,
  String? activeRoute, {
  required bool hubOpen,
}) {
  final route = activeRoute ?? '';
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final active = switch (item.kind) {
      BottomNavItemKind.you => hubOpen,
      BottomNavItemKind.home => !hubOpen && route == Destinations.home,
      BottomNavItemKind.tab =>
        !hubOpen && bottomNavTabMatchesRoute(item.tab!, route),
      BottomNavItemKind.library =>
        !hubOpen && bottomNavLibraryMatchesRoute(item.libraryId!, route),
    };
    if (active) return i;
  }
  return null;
}

enum BottomNavHubAction { saved, shuffle, syncPlay }

/// A tile in the You hub: a destination that isn't pinned, or an action.
class BottomNavHubTile {
  final BottomNavTab? tab;
  final BottomNavHubAction? action;

  const BottomNavHubTile.tab(BottomNavTab this.tab) : action = null;
  const BottomNavHubTile.action(BottomNavHubAction this.action) : tab = null;

  @override
  bool operator ==(Object other) =>
      other is BottomNavHubTile && other.tab == tab && other.action == action;

  @override
  int get hashCode => Object.hash(tab, action);

  @override
  String toString() => 'BottomNavHubTile(${tab?.name ?? action?.name})';
}

/// Tiles for the You hub, in the order they are drawn: saved media first
/// because it matters most offline, then every destination that is offered
/// but not on the bar, then the actions.
///
/// [alsoOnBar] names tabs the bar shows outside its tab row, like Split's
/// search button.
List<BottomNavHubTile> resolveHubTiles({
  required BottomNavTabGates gates,
  required List<BottomNavBarItem> barItems,
  required bool Function(BottomNavTab tab) isAvailable,
  required bool savedAvailable,
  required bool shuffle,
  required bool syncPlay,
  Set<BottomNavTab> alsoOnBar = const {},
}) {
  final onBar = {
    ...alsoOnBar,
    for (final item in barItems)
      if (item.tab != null) item.tab!,
  };
  return [
    if (savedAvailable) const BottomNavHubTile.action(BottomNavHubAction.saved),
    for (final tab in BottomNavTab.values)
      if (!onBar.contains(tab) && gates.offers(tab) && isAvailable(tab))
        BottomNavHubTile.tab(tab),
    if (shuffle) const BottomNavHubTile.action(BottomNavHubAction.shuffle),
    if (syncPlay) const BottomNavHubTile.action(BottomNavHubAction.syncPlay),
  ];
}

import 'user_preferences.dart';

/// Destinations that can be pinned between Home and You on the mobile bottom
/// navbar. The names are the wire format of [UserPreferences.bottomNavbarTabs],
/// so renaming one breaks every synced profile that holds it.
// 06.11, Sid ("y mettre le raccourci télécommande"): remoteControl opens
// RemoteControlScreen as a panel (like Settings) rather than a go_router
// route, same special-cased shape as libraries - see openBottomNavTab's own
// comment and its two call sites (you_hub_sheet.dart, bottom_navbar.dart).
enum BottomNavTab {
  search,
  libraries,
  favorites,
  genres,
  liveTv,
  discover,
  folders,
  remoteControl,
}

// 06.11, Sid ("et pouvoir en épingler plus que 3 - me laisser le choix"):
// the ceiling the picker screen offers; the actual number in effect is
// UserPreferences.maxPinnedBottomNavTabs (default kDefaultMaxPinnedBottomNavTabs),
// adjustable per profile like everything else on this bar.
const int kDefaultMaxPinnedBottomNavTabs = 3;
const int kMaxPinnedBottomNavTabsCeiling = 7;

// Libraries sits second so a user on default settings keeps it on the bar.
const List<BottomNavTab> _autoOrder = [
  BottomNavTab.search,
  BottomNavTab.libraries,
  BottomNavTab.favorites,
  BottomNavTab.liveTv,
  BottomNavTab.discover,
  BottomNavTab.genres,
  BottomNavTab.folders,
];

final Map<String, BottomNavTab> _byName = {
  for (final tab in BottomNavTab.values) tab.name.toLowerCase(): tab,
};

// 06.11, Sid ("à la place de recherche, favoris etc... juste me donner le
// choix de mettre à la place... jamais utilisé le bouton recherche"): a
// pinned slot is either a fixed BottomNavTab, or one specific library -
// unified so the same ordered list (and the same picker screen) can mix
// both, and a library can take over any slot a tab would otherwise sit in.
sealed class PinnedNavItem {
  const PinnedNavItem();

  /// Wire format for [UserPreferences.bottomNavbarTabs] - a BottomNavTab's
  /// own name, or "lib:<id>" for a library. A tab's name is never allowed to
  /// contain ':' (it's a Dart enum member name), so parsing back is
  /// unambiguous.
  String get wireValue;
}

class PinnedTab extends PinnedNavItem {
  final BottomNavTab tab;
  const PinnedTab(this.tab);

  @override
  String get wireValue => tab.name;

  @override
  bool operator ==(Object other) => other is PinnedTab && other.tab == tab;

  @override
  int get hashCode => tab.hashCode;

  @override
  String toString() => 'PinnedTab(${tab.name})';
}

class PinnedLibrary extends PinnedNavItem {
  final String libraryId;
  const PinnedLibrary(this.libraryId);

  @override
  String get wireValue => 'lib:$libraryId';

  @override
  bool operator ==(Object other) =>
      other is PinnedLibrary && other.libraryId == libraryId;

  @override
  int get hashCode => libraryId.hashCode;

  @override
  String toString() => 'PinnedLibrary($libraryId)';
}

/// Reads a stored pin list. Unknown/malformed entries, which a newer client
/// may have synced, are dropped along with duplicates and anything past
/// [maxPins].
List<PinnedNavItem> parsePinnedBottomNavTabs(
  String raw, {
  int maxPins = kDefaultMaxPinnedBottomNavTabs,
}) {
  final pins = <PinnedNavItem>[];
  for (final part in raw.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    PinnedNavItem? item;
    if (trimmed.startsWith('lib:')) {
      final id = trimmed.substring(4);
      if (id.isNotEmpty) item = PinnedLibrary(id);
    } else {
      final tab = _byName[trimmed.toLowerCase()];
      if (tab != null) item = PinnedTab(tab);
    }
    if (item == null || pins.contains(item)) continue;
    pins.add(item);
    if (pins.length == maxPins) break;
  }
  return pins;
}

String serializePinnedBottomNavTabs(
  Iterable<PinnedNavItem> items, {
  int maxPins = kDefaultMaxPinnedBottomNavTabs,
}) =>
    items.take(maxPins).map((i) => i.wireValue).join(',');

/// Whether [raw] leaves the pins to be picked automatically. A list whose
/// entries are all unknown counts, so a profile from a newer client falls
/// back to something sensible instead of an empty bar.
bool isAutomaticBottomNavTabs(String raw) =>
    parsePinnedBottomNavTabs(raw).isEmpty;

/// The settings that decide whether a [BottomNavTab] is on offer at all. Only
/// preferences and plugin state feed it, never loaded data, so the pins and
/// their colours don't shift while libraries are still loading. A pinned
/// library's own existence is checked separately (resolveBarItems'
/// availableLibraryIds) - this gate only concerns the fixed tabs.
class BottomNavTabGates {
  final bool kidsMode;
  final bool showLibraries;
  final bool showFavorites;
  final bool showGenres;
  final bool showLiveTv;
  final bool showSeerr;
  final bool seerrAvailable;
  final bool folderView;

  const BottomNavTabGates({
    this.kidsMode = false,
    this.showLibraries = true,
    this.showFavorites = true,
    this.showGenres = true,
    this.showLiveTv = false,
    this.showSeerr = true,
    this.seerrAvailable = false,
    this.folderView = false,
  });

  factory BottomNavTabGates.fromPreferences(
    UserPreferences prefs, {
    required bool seerrAvailable,
  }) {
    return BottomNavTabGates(
      kidsMode: prefs.get(UserPreferences.kidsModeEnabled),
      showLibraries: prefs.get(UserPreferences.showLibrariesInToolbar),
      showFavorites: prefs.get(UserPreferences.showFavoritesButton),
      showGenres: prefs.get(UserPreferences.showGenresButton),
      showLiveTv: prefs.get(UserPreferences.showLiveTvButton),
      showSeerr: prefs.get(UserPreferences.showSeerrButton),
      seerrAvailable: seerrAvailable,
      folderView: prefs.get(UserPreferences.enableFolderView),
    );
  }

  // Kids Mode drops Libraries (the My Media row stands in), Live TV (its route
  // bounces home) and Seerr.
  bool offers(BottomNavTab tab) => switch (tab) {
        BottomNavTab.search => true,
        BottomNavTab.libraries => !kidsMode && showLibraries,
        BottomNavTab.favorites => showFavorites,
        BottomNavTab.genres => showGenres,
        BottomNavTab.liveTv => !kidsMode && showLiveTv,
        BottomNavTab.discover => !kidsMode && showSeerr && seerrAvailable,
        BottomNavTab.folders => folderView,
        // 06.11, Sid ("y mettre le raccourci télécommande"): always
        // offered, no server feature/toggle gates it the way Live TV or
        // Seerr do - but still excluded from Kids Mode, a remote isn't
        // something a kid profile needs either.
        BottomNavTab.remoteControl => !kidsMode,
      };

  /// The items the bar shows between Home and You. Automatic pins follow the
  /// nav button switches without anything being stored (always plain tabs -
  /// an automatic pin never guesses a library). Explicit pins are only
  /// filtered, never topped up, so turning a button off doesn't slip an
  /// unchosen tab onto the bar. [maxPins] caps both paths the same way. A
  /// pinned library always passes this gate - its real availability (does
  /// it still exist) is checked downstream in resolveBarItems.
  List<PinnedNavItem> resolvePins(
    String raw, {
    int maxPins = kDefaultMaxPinnedBottomNavTabs,
  }) {
    final explicit = parsePinnedBottomNavTabs(raw, maxPins: maxPins);
    if (explicit.isNotEmpty) {
      return explicit.where((item) {
        if (item is PinnedTab) return offers(item.tab);
        return true;
      }).toList();
    }
    return _autoOrder.where(offers).map(PinnedTab.new).take(maxPins).toList();
  }
}

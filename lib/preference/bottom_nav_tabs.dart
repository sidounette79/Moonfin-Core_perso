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

/// Reads a stored pin list. Unknown names, which a newer client may have
/// synced, are dropped along with duplicates and anything past [maxPins].
List<BottomNavTab> parsePinnedBottomNavTabs(
  String raw, {
  int maxPins = kDefaultMaxPinnedBottomNavTabs,
}) {
  final pins = <BottomNavTab>[];
  for (final part in raw.split(',')) {
    final tab = _byName[part.trim().toLowerCase()];
    if (tab == null || pins.contains(tab)) continue;
    pins.add(tab);
    if (pins.length == maxPins) break;
  }
  return pins;
}

String serializePinnedBottomNavTabs(
  Iterable<BottomNavTab> tabs, {
  int maxPins = kDefaultMaxPinnedBottomNavTabs,
}) =>
    tabs.take(maxPins).map((t) => t.name).join(',');

/// Whether [raw] leaves the pins to be picked automatically. A list whose
/// names are all unknown counts, so a profile from a newer client falls back
/// to something sensible instead of an empty bar.
bool isAutomaticBottomNavTabs(String raw) =>
    parsePinnedBottomNavTabs(raw).isEmpty;

/// The settings that decide whether a [BottomNavTab] is on offer at all. Only
/// preferences and plugin state feed it, never loaded data, so the pins and
/// their colours don't shift while libraries are still loading.
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

  /// The tabs the bar shows between Home and You. Automatic pins follow the
  /// nav button switches without anything being stored. Explicit pins are
  /// only filtered, never topped up, so turning a button off doesn't slip an
  /// unchosen tab onto the bar. [maxPins] caps both paths the same way.
  List<BottomNavTab> resolvePins(
    String raw, {
    int maxPins = kDefaultMaxPinnedBottomNavTabs,
  }) {
    final explicit = parsePinnedBottomNavTabs(raw, maxPins: maxPins);
    if (explicit.isNotEmpty) return explicit.where(offers).toList();
    return _autoOrder.where(offers).take(maxPins).toList();
  }
}

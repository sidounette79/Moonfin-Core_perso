import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/bottom_nav_tabs.dart';
import 'package:moonfin/ui/widgets/bottom_nav/bottom_nav_model.dart';

void main() {
  group('resolveBarItems', () {
    test('Home, the pins and You, with slots in order', () {
      final items = resolveBarItems(const BottomNavTabGates(), '');
      expect(items, const [
        BottomNavBarItem.home(),
        BottomNavBarItem.tab(BottomNavTab.search, 1),
        BottomNavBarItem.tab(BottomNavTab.libraries, 2),
        BottomNavBarItem.tab(BottomNavTab.favorites, 3),
        BottomNavBarItem.you(4),
      ]);
    });

    test('a pin waiting on its data keeps the slots after it', () {
      final items = resolveBarItems(
        const BottomNavTabGates(),
        '',
        isAvailable: (tab) => tab != BottomNavTab.libraries,
      );
      expect(items, const [
        BottomNavBarItem.home(),
        BottomNavBarItem.tab(BottomNavTab.search, 1),
        BottomNavBarItem.tab(BottomNavTab.favorites, 3),
        BottomNavBarItem.you(4),
      ]);
    });

    test('Split leaves Search to its own button', () {
      final items = resolveBarItems(
        const BottomNavTabGates(),
        '',
        withoutSearch: true,
      );
      expect(items.map((i) => i.id), ['home', 'libraries', 'favorites', 'you']);
    });

    // 06.11, Sid ("à la place de recherche, favoris etc... choisir des
    // bibliothèques spécifiques"): a pinned library takes a real slot,
    // same as a tab would, but only once it's actually in
    // availableLibraryIds - otherwise it's dropped like an unavailable tab.
    test('a pinned library becomes a library item once it is available', () {
      final items = resolveBarItems(
        const BottomNavTabGates(),
        'search,lib:42',
        availableLibraryIds: {'42'},
      );
      expect(items, const [
        BottomNavBarItem.home(),
        BottomNavBarItem.tab(BottomNavTab.search, 1),
        BottomNavBarItem.library('42', 2),
        BottomNavBarItem.you(3),
      ]);
    });

    test('a pinned library not yet available is dropped, slots keep its gap',
        () {
      final items = resolveBarItems(
        const BottomNavTabGates(),
        'search,lib:42,favorites',
        availableLibraryIds: const {},
      );
      expect(items, const [
        BottomNavBarItem.home(),
        BottomNavBarItem.tab(BottomNavTab.search, 1),
        BottomNavBarItem.tab(BottomNavTab.favorites, 3),
        BottomNavBarItem.you(4),
      ]);
    });
  });

  group('activeBarIndex', () {
    final items = resolveBarItems(
      const BottomNavTabGates(folderView: true),
      'search,libraries,folders',
    );

    int? active(String? route, {bool hubOpen = false}) =>
        activeBarIndex(items, route, hubOpen: hubOpen);

    test('matches each tab on its own screens', () {
      expect(active('/home'), 0);
      expect(active('/search'), 1);
      expect(active('/library/abc'), 2);
      expect(active('/music/abc'), 2);
      expect(active('/books/abc'), 2);
      expect(active('/folders'), 3);
      expect(active('/folder/xyz'), 3);
    });

    test('lights nothing on a screen that belongs to no tab', () {
      expect(active('/item/123'), isNull);
      expect(active(null), isNull);
    });

    test('You takes over while the hub is open', () {
      expect(active('/home', hubOpen: true), items.length - 1);
    });

    test('a route that only starts with a tab name doesn\'t match it', () {
      expect(bottomNavTabMatchesRoute(BottomNavTab.libraries, '/library-x'),
          isFalse);
      expect(bottomNavTabMatchesRoute(BottomNavTab.discover, '/seerr/requests'),
          isTrue);
    });

    // 06.11, Sid: a library id can prefix another (server-assigned, no
    // guarantee against it) - matched as a whole path segment, not a
    // plain prefix.
    test('a pinned library matches its own route by whole segment, not prefix',
        () {
      expect(bottomNavLibraryMatchesRoute('42', '/library/42'), isTrue);
      expect(bottomNavLibraryMatchesRoute('42', '/library/42/suggestions'),
          isTrue);
      expect(bottomNavLibraryMatchesRoute('42', '/library/420'), isFalse);
      expect(bottomNavLibraryMatchesRoute('42', '/music/42'), isTrue);
      expect(bottomNavLibraryMatchesRoute('42', '/library/7'), isFalse);
    });
  });

  group('resolveHubTiles', () {
    List<BottomNavHubTile> tiles({
      BottomNavTabGates gates = const BottomNavTabGates(),
      String pins = '',
      bool saved = false,
      bool shuffle = true,
      bool syncPlay = false,
      Set<BottomNavTab> alsoOnBar = const {},
    }) =>
        resolveHubTiles(
          gates: gates,
          barItems: resolveBarItems(gates, pins),
          isAvailable: (_) => true,
          savedAvailable: saved,
          shuffle: shuffle,
          syncPlay: syncPlay,
          alsoOnBar: alsoOnBar,
        );

    test('holds everything offered that isn\'t on the bar', () {
      expect(tiles(saved: true, syncPlay: true), const [
        BottomNavHubTile.action(BottomNavHubAction.saved),
        BottomNavHubTile.tab(BottomNavTab.genres),
        BottomNavHubTile.action(BottomNavHubAction.shuffle),
        BottomNavHubTile.action(BottomNavHubAction.syncPlay),
      ]);
    });

    test('Kids Mode keeps what children may use', () {
      final kids = tiles(
        gates: const BottomNavTabGates(
          kidsMode: true,
          showLiveTv: true,
          seerrAvailable: true,
          folderView: true,
        ),
        saved: true,
      );
      expect(kids.map((t) => t.tab), isNot(contains(BottomNavTab.libraries)));
      expect(kids.map((t) => t.tab), isNot(contains(BottomNavTab.liveTv)));
      expect(kids.map((t) => t.tab), isNot(contains(BottomNavTab.discover)));
      expect(kids, contains(const BottomNavHubTile.tab(BottomNavTab.folders)));
      expect(kids,
          contains(const BottomNavHubTile.action(BottomNavHubAction.saved)));
    });

    test('Split doesn\'t repeat Search in the hub', () {
      final split = tiles(pins: 'libraries', alsoOnBar: {BottomNavTab.search});
      expect(split.map((t) => t.tab), isNot(contains(BottomNavTab.search)));
    });
  });
}

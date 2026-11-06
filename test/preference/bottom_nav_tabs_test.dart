import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/bottom_nav_tabs.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PreferenceStore> _store([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final store = PreferenceStore();
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parsePinnedBottomNavTabs', () {
    test('reads names case-insensitively and ignores whitespace', () {
      expect(
        parsePinnedBottomNavTabs(' Search , LIVETV,folders'),
        [
          const PinnedTab(BottomNavTab.search),
          const PinnedTab(BottomNavTab.liveTv),
          const PinnedTab(BottomNavTab.folders),
        ],
      );
    });

    test('drops unknown names and duplicates', () {
      expect(
        parsePinnedBottomNavTabs('podcasts,favorites,favorites,,genres'),
        [
          const PinnedTab(BottomNavTab.favorites),
          const PinnedTab(BottomNavTab.genres),
        ],
      );
    });

    // 06.11, Sid ("choisir des bibliothèques spécifiques"): a pin can also
    // be a specific library, wire-encoded as "lib:<id>" - distinct from a
    // tab name, no ambiguity parsing one back.
    test('parses a pinned library alongside tabs', () {
      expect(
        parsePinnedBottomNavTabs('search,lib:42,favorites'),
        [
          const PinnedTab(BottomNavTab.search),
          const PinnedLibrary('42'),
          const PinnedTab(BottomNavTab.favorites),
        ],
      );
    });

    test('keeps at most three by default', () {
      expect(
        parsePinnedBottomNavTabs('search,libraries,favorites,genres'),
        hasLength(kDefaultMaxPinnedBottomNavTabs),
      );
    });

    test('respects a custom maxPins', () {
      expect(
        parsePinnedBottomNavTabs(
          'search,libraries,favorites,genres',
          maxPins: 2,
        ),
        hasLength(2),
      );
    });

    test('round-trips through serialize', () {
      const items = [PinnedTab(BottomNavTab.discover), PinnedTab(BottomNavTab.search)];
      expect(
        parsePinnedBottomNavTabs(serializePinnedBottomNavTabs(items)),
        items,
      );
    });

    test('a pinned library round-trips through serialize too', () {
      const items = [PinnedLibrary('7'), PinnedTab(BottomNavTab.search)];
      expect(
        parsePinnedBottomNavTabs(serializePinnedBottomNavTabs(items)),
        items,
      );
    });

    test('empty or all-unknown lists count as automatic', () {
      expect(isAutomaticBottomNavTabs(''), isTrue);
      expect(isAutomaticBottomNavTabs('podcasts,radio'), isTrue);
      expect(isAutomaticBottomNavTabs('search'), isFalse);
    });
  });

  group('automatic pins', () {
    test('default settings pin Search, Libraries and Favorites', () {
      expect(const BottomNavTabGates().resolvePins(''), [
        const PinnedTab(BottomNavTab.search),
        const PinnedTab(BottomNavTab.libraries),
        const PinnedTab(BottomNavTab.favorites),
      ]);
    });

    test('a turned off button is skipped for the next offered tab', () {
      const gates = BottomNavTabGates(showFavorites: false, showLiveTv: true);
      expect(gates.resolvePins(''), [
        const PinnedTab(BottomNavTab.search),
        const PinnedTab(BottomNavTab.libraries),
        const PinnedTab(BottomNavTab.liveTv),
      ]);
    });

    test('Kids Mode leaves out Libraries, Live TV and Seerr', () {
      const gates = BottomNavTabGates(
        kidsMode: true,
        showLiveTv: true,
        seerrAvailable: true,
      );
      expect(gates.resolvePins(''), [
        const PinnedTab(BottomNavTab.search),
        const PinnedTab(BottomNavTab.favorites),
        const PinnedTab(BottomNavTab.genres),
      ]);
    });

    test('Seerr only counts once the plugin reports it available', () {
      const without = BottomNavTabGates(showLibraries: false);
      const withSeerr = BottomNavTabGates(
        showLibraries: false,
        seerrAvailable: true,
      );
      expect(
        without.resolvePins(''),
        isNot(contains(const PinnedTab(BottomNavTab.discover))),
      );
      expect(
        withSeerr.resolvePins(''),
        contains(const PinnedTab(BottomNavTab.discover)),
      );
    });

    // Automatic pins never guess a library - only an explicit pick can be
    // one (BottomNavTabGates.resolvePins' own comment).
    test('automatic pins are never libraries', () {
      expect(
        const BottomNavTabGates().resolvePins(''),
        everyElement(isA<PinnedTab>()),
      );
    });
  });

  group('explicit pins', () {
    test('keep their order', () {
      expect(const BottomNavTabGates().resolvePins('favorites,search'), [
        const PinnedTab(BottomNavTab.favorites),
        const PinnedTab(BottomNavTab.search),
      ]);
    });

    test('drop a tab that is no longer offered without topping up', () {
      const gates = BottomNavTabGates(showGenres: false);
      expect(
        gates.resolvePins('genres,search'),
        [const PinnedTab(BottomNavTab.search)],
      );
    });

    test('a pinned library always passes the gate, even for a removed library',
        () {
      // resolvePins itself never checks whether the library still exists -
      // that's resolveBarItems' job (availableLibraryIds), which this
      // preference-layer test doesn't exercise.
      const gates = BottomNavTabGates();
      expect(
        gates.resolvePins('lib:99,search'),
        [const PinnedLibrary('99'), const PinnedTab(BottomNavTab.search)],
      );
    });
  });

  group('upgrading from the old bottom navbar', () {
    const signedIn = {
      'pref_last_server_id': 'srv',
      'pref_last_user_id': 'usr',
      'pref_navbar_position_srv_usr': 'bottom',
      'pref_show_favorites_button_srv_usr': false,
    };

    test('lands on Dock with pins from the toggles and writes nothing',
        () async {
      final store = await _store(signedIn);
      final prefs = UserPreferences(store);

      expect(prefs.get(UserPreferences.navbarPosition), NavbarPosition.bottom);
      expect(prefs.get(UserPreferences.bottomNavbarStyle),
          BottomNavbarStyle.dock);

      final gates = BottomNavTabGates.fromPreferences(
        prefs,
        seerrAvailable: false,
      );
      expect(gates.resolvePins(prefs.get(UserPreferences.bottomNavbarTabs)), [
        const PinnedTab(BottomNavTab.search),
        const PinnedTab(BottomNavTab.libraries),
        const PinnedTab(BottomNavTab.genres),
      ]);

      // Other constructor steps seed their own keys, so only the navbar's
      // own keys are checked.
      expect(
        store.keys.where((k) => k.startsWith('pref_bottom_navbar')),
        isEmpty,
      );
      expect(prefs.containsPreference(UserPreferences.bottomNavbarStyle),
          isFalse);
      expect(prefs.containsPreference(UserPreferences.bottomNavbarTabs),
          isFalse);
    });

    test('both new preferences are stored per server and user', () async {
      final store = await _store(signedIn);
      final prefs = UserPreferences(store);

      await prefs.set(UserPreferences.bottomNavbarStyle,
          BottomNavbarStyle.strip);
      await prefs.set(UserPreferences.bottomNavbarTabs, 'search');

      expect(store.getString('pref_bottom_navbar_style_srv_usr'), 'strip');
      expect(store.getString('pref_bottom_navbar_tabs_srv_usr'), 'search');
    });
  });
}

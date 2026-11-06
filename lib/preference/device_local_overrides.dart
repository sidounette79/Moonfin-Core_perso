import 'package:jellyfin_preference/jellyfin_preference.dart';

/// 06.11, Sid ("là, quand je change sur un, ca change instantanément les
/// autres... mais je voudrais juste pour la barre de navigation"): most
/// synced settings in PluginSyncService legitimately follow her per-profile
/// sync (mobile/tv/desktop/global, see synced_fields.dart) - that's the
/// whole point. But her box voiture shares the same 'tv' profile as her
/// other TVs (both detected as PlatformDetection.isTV), and she wants ONE
/// field (navbarPosition, so it can stay a sidebar there for the CarPlay-
/// style launcher dock) to stop following that profile on THIS physical
/// device only, without opting out any other field or any other device.
///
/// Deliberately NOT scoped per signed-in user the way BazarrPreferences is -
/// this is a property of the physical device/profile install, not of who's
/// logged into it. A plain key on this device's own local store, never
/// touched by PluginSyncService's pull/push.
class DeviceLocalOverrides {
  final PreferenceStore _store;

  DeviceLocalOverrides(this._store);

  static const String _key = 'device_local_override_fields';

  Set<String> get overriddenServerKeys {
    final raw = _store.getString(_key);
    if (raw == null || raw.isEmpty) return const {};
    return raw.split(',').where((s) => s.isNotEmpty).toSet();
  }

  bool isOverridden(String serverKey) =>
      overriddenServerKeys.contains(serverKey);

  Future<void> setOverridden(String serverKey, bool overridden) async {
    final current = overriddenServerKeys.toSet();
    if (overridden) {
      current.add(serverKey);
    } else {
      current.remove(serverKey);
    }
    await _store.setString(_key, current.join(','));
  }
}

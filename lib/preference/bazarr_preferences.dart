import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../auth/repositories/session_repository.dart';

/// Direct Bazarr connection (URL + API key), separate from Emby's own
/// subtitle search. Sid: "j'ai plein dans bazarr que je peux ajouter
/// facilement par rapport à emby... donc le mien c'est lien direct vers
/// bazarr" - deliberately NOT routed through a server-side proxy (unlike
/// seerr_preferences.dart's Moonfin plugin pattern), since this isn't a
/// Moonfin server feature, just the client talking to a Bazarr instance
/// on her own network directly.
class BazarrPreferences {
  // 06.11, Sid ("je n'aie pas besoin de l'activer sur chaque appareil...
  // on peut le mettre en dur dans le code ?") - the repo is PUBLIC on
  // GitHub, so the API key is never committed in plain text: it only
  // exists as a GitHub Actions secret (BAZARR_DEFAULT_API_KEY), baked
  // into the compiled binary via --dart-define in build-android.sh.
  // Used as a fallback ONLY when this specific user has never saved their
  // own value (see the getters below) - a manual change from the config
  // screen always wins from then on. The server URL is already publicly
  // reachable (bazarr.sidounette.ch, exposed via Caddy) so it's hardcoded
  // directly here - only the key actually needs to stay out of the repo.
  static const String _defaultServerUrl = 'https://bazarr.sidounette.ch';
  static const String _defaultApiKey = String.fromEnvironment(
    'BAZARR_DEFAULT_API_KEY',
  );

  final PreferenceStore _store;
  final SessionRepository _session;

  BazarrPreferences(this._store, this._session);

  String _userKey(String key) {
    final uid = _session.activeUserId ?? '';
    return 'bazarr_${key}_$uid';
  }

  // Auto-enabled once a default key is baked in and nothing was ever
  // explicitly saved - this is exactly what "pas besoin de l'activer sur
  // chaque appareil" asked for. An explicit `setEnabled(false)` (the
  // toggle in BazarrConfigScreen) always overrides this from then on.
  bool get enabled =>
      _store.getBool(_userKey('enabled')) ?? _defaultApiKey.isNotEmpty;
  Future<void> setEnabled(bool value) => _store.setBool(_userKey('enabled'), value);

  String get serverUrl =>
      _store.getString(_userKey('server_url')) ?? _defaultServerUrl;
  Future<void> setServerUrl(String value) => _store.setString(_userKey('server_url'), value);

  String get apiKey =>
      _store.getString(_userKey('api_key')) ?? _defaultApiKey;
  Future<void> setApiKey(String value) => _store.setString(_userKey('api_key'), value);

  bool get lastConnectionSuccess =>
      _store.getBool(_userKey('last_connection_success')) ?? false;
  Future<void> setLastConnectionSuccess(bool value) =>
      _store.setBool(_userKey('last_connection_success'), value);

  Future<void> clearAll() async {
    for (final key in ['enabled', 'server_url', 'api_key', 'last_connection_success']) {
      await _store.remove(_userKey(key));
    }
  }
}

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
  final PreferenceStore _store;
  final SessionRepository _session;

  BazarrPreferences(this._store, this._session);

  String _userKey(String key) {
    final uid = _session.activeUserId ?? '';
    return 'bazarr_${key}_$uid';
  }

  bool get enabled => _store.getBool(_userKey('enabled')) ?? false;
  Future<void> setEnabled(bool value) => _store.setBool(_userKey('enabled'), value);

  String get serverUrl => _store.getString(_userKey('server_url')) ?? '';
  Future<void> setServerUrl(String value) => _store.setString(_userKey('server_url'), value);

  String get apiKey => _store.getString(_userKey('api_key')) ?? '';
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

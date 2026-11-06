import 'dart:convert';

import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../auth/repositories/session_repository.dart';

/// A chosen target: remembered as its device id (stable across sessions)
/// plus the name it had when picked, so the button still shows something
/// sensible for a TV that's currently off/unreachable (no active session to
/// read a fresh name from).
class RemoteControlTarget {
  final String deviceId;
  final String deviceName;

  const RemoteControlTarget({required this.deviceId, required this.deviceName});

  Map<String, dynamic> toJson() => {'id': deviceId, 'name': deviceName};

  factory RemoteControlTarget.fromJson(Map<String, dynamic> json) =>
      RemoteControlTarget(
        deviceId: json['id'] as String? ?? '',
        deviceName: json['name'] as String? ?? '',
      );
}

/// 06.11, Sid ("un onglet purement telecommande... 3 bouton pour les trois
/// TV en haut"): which up-to-3 sessions the quick-select row in
/// RemoteControlScreen offers, remembered by device id rather than guessed
/// from the client name - a plain "is this a TV" heuristic doesn't hold
/// (she picked "TV BOX BOUBOU", which still runs the stock Emby Android
/// client, not yet CarbaTV/Moonfin - same shape as BazarrPreferences, one
/// saved value per signed-in user.
class RemoteControlPreferences {
  final PreferenceStore _store;
  final SessionRepository _session;

  RemoteControlPreferences(this._store, this._session);

  String _userKey(String key) {
    final uid = _session.activeUserId ?? '';
    return 'remote_control_${key}_$uid';
  }

  static const int maxTargets = 3;

  List<RemoteControlTarget> get targets {
    final raw = _store.getString(_userKey('targets'));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .cast<Map<String, dynamic>>()
          .map(RemoteControlTarget.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> setTargets(List<RemoteControlTarget> value) {
    final trimmed = value.take(maxTargets).toList();
    return _store.setString(
      _userKey('targets'),
      jsonEncode(trimmed.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> clearTargets() => _store.remove(_userKey('targets'));
}

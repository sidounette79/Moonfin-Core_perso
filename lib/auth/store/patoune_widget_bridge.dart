import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// 24.11, Sid — alimente les widgets d'écran d'accueil « séries à voir ».
///
/// Les widgets interrogent Patoune TV eux-mêmes, avec le jeton Emby : le
/// serveur retrouve le compte Patoune TV correspondant grâce au pont que
/// son webhook Emby maintient déjà (integrations.embyUsername). Mais un
/// widget ne peut pas lire FlutterSecureStorage, où vit le vrai jeton :
/// c'est un BroadcastReceiver, hors du moteur Flutter. On en dépose donc
/// une copie dans les shared_preferences, que le Kotlin relit.
///
/// Android seulement : les widgets n'existent que là, et il ne sert à
/// rien d'écrire une copie en clair du jeton sur les autres plateformes.
class PatouneWidgetBridge {
  static const _tokenKey = 'patoune_widget_emby_token';
  static const _baseUrlKey = 'patoune_widget_base_url';

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Le jeton est publié depuis chaque endroit où l'app le pose sur son
  /// client (connexion, restauration au démarrage, changement de
  /// session) : on évite d'écrire plusieurs fois la même valeur.
  static String? _dernierPublie;

  /// Appelé à chaque enregistrement de jeton. Multi-serveur : c'est le
  /// dernier serveur connecté qui alimente les widgets — elle n'en a
  /// qu'un, et un widget ne saurait de toute façon pas lequel choisir.
  static Future<void> publishToken(String token) async {
    if (!_supported || token.isEmpty || token == _dernierPublie) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      _dernierPublie = token;
    } catch (_) {
      // Un widget qui ne se met pas à jour ne doit jamais faire échouer
      // une connexion.
    }
  }

  /// L'URL de l'instance Patoune TV. Le Kotlin a sa propre valeur par
  /// défaut, donc n'écrire que si elle est explicitement réglée.
  static Future<void> publishBaseUrl(String baseUrl) async {
    if (!_supported || baseUrl.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_baseUrlKey, baseUrl);
    } catch (_) {
      // idem
    }
  }

  /// À la déconnexion : les widgets doivent cesser d'afficher ses séries.
  static Future<void> clear() async {
    if (!_supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      _dernierPublie = null;
    } catch (_) {
      // idem
    }
  }
}

package org.moonfin.androidtv.widget

import android.content.Context

/**
 * 24.11, Sid — réglages des widgets « séries à voir ».
 *
 * Le jeton Emby vit normalement dans FlutterSecureStorage, qu'un
 * AppWidgetProvider ne sait pas lire : un widget est un BroadcastReceiver,
 * il tourne hors du moteur Flutter et n'a aucun accès au coffre. Le côté
 * Dart en dépose donc une copie via shared_preferences, que ce fichier
 * relit — lisible par cette app seule (bac à sable Android), mais non
 * chiffrée. Compromis assumé et habituel pour un widget ; sans ça, le
 * widget ne pourrait rien afficher tant que l'app n'est pas ouverte.
 *
 * On lit directement le magasin de shared_preferences plutôt que de
 * passer par un MethodChannel : un canal n'existe que pendant que le
 * moteur Flutter tourne, ce qui n'est jamais garanti pour un widget. Et
 * ça évite de toucher MainActivity, partagé avec la version Android TV.
 */
object PatouneWidgetConfig {
    /** Nom du magasin écrit par le plugin shared_preferences. */
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"

    /** Le plugin préfixe toutes ses clés. */
    private const val KEY_BASE_URL = "flutter.patoune_widget_base_url"
    private const val KEY_EMBY_TOKEN = "flutter.patoune_widget_emby_token"

    /** Son instance. Surchargée par la préférence si Dart en écrit une. */
    const val DEFAULT_BASE_URL = "https://patounetv.sidounette.ch"

    fun baseUrl(context: Context): String =
        read(context, KEY_BASE_URL) ?: DEFAULT_BASE_URL

    fun embyToken(context: Context): String? = read(context, KEY_EMBY_TOKEN)

    private fun read(context: Context, key: String): String? =
        runCatching {
            context
                .getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                .getString(key, null)
                ?.takeIf { it.isNotBlank() }
        }.getOrNull()
}

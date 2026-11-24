package org.moonfin.androidtv.widget

import android.content.Context
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

/** Une ligne de widget, quelle que soit la source. */
data class SeriesEntry(
    val title: String,
    /** "S10E01 Old Wounds", ou null si l'épisode n'est pas identifié. */
    val episodeLabel: String?,
    /** 3e ligne : "6 épisodes non vus" ou "dans 45 jours". */
    val detail: String?,
)

/**
 * Appels à Patoune TV pour les widgets.
 *
 * HttpURLConnection et org.json plutôt qu'OkHttp/Moshi : ce code tourne
 * dans le processus du widget, pas dans l'app, et trois requêtes GET ne
 * justifient pas d'y traîner des dépendances.
 *
 * Volontairement synchrone : appelé depuis RemoteViewsFactory.onDataSetChanged(),
 * qui s'exécute déjà hors du fil principal et attend que les données soient
 * prêtes avant de dessiner.
 */
object PatouneApi {
    private const val TAG = "PatouneWidget"
    private const val TIMEOUT_MS = 10_000

    fun fetch(context: Context, kind: WidgetKind): List<SeriesEntry> {
        val token = PatouneWidgetConfig.embyToken(context) ?: return emptyList()
        val url = "${PatouneWidgetConfig.baseUrl(context).trimEnd('/')}/api/widget/${kind.path}?limit=10"

        return try {
            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                setRequestProperty("X-Emby-Token", token)
                setRequestProperty("Accept", "application/json")
                connectTimeout = TIMEOUT_MS
                readTimeout = TIMEOUT_MS
            }
            try {
                if (connection.responseCode != 200) {
                    Log.w(TAG, "${kind.path}: HTTP ${connection.responseCode}")
                    return emptyList()
                }
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                parse(context, body, kind)
            } finally {
                connection.disconnect()
            }
        } catch (e: Exception) {
            // Le widget affichera son message « rien à afficher » : une
            // panne réseau ne doit pas le laisser sur des données fausses.
            Log.w(TAG, "${kind.path}: ${e.message}")
            emptyList()
        }
    }

    private fun parse(context: Context, body: String, kind: WidgetKind): List<SeriesEntry> {
        val items = JSONObject(body).optJSONArray("items") ?: return emptyList()
        return (0 until items.length()).mapNotNull { i ->
            val o = items.optJSONObject(i) ?: return@mapNotNull null
            val title = o.optString("title").takeIf { it.isNotBlank() } ?: return@mapNotNull null
            SeriesEntry(
                title = title,
                episodeLabel = episodeLabel(o),
                detail = kind.detail(context, o),
            )
        }
    }

    /** "S10E01 That Sinking Feeling" */
    private fun episodeLabel(o: JSONObject): String? {
        val season = o.optInt("seasonNumber", -1)
        val episode = o.optInt("episodeNumber", -1)
        if (season < 0 || episode < 0) return null
        val code = "S%02dE%02d".format(season, episode)
        val name = o.optString("episodeName").takeIf { it.isNotBlank() && it != "null" }
        return if (name != null) "$code $name" else code
    }
}

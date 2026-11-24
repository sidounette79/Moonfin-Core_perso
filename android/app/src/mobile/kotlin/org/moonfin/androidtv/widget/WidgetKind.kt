package org.moonfin.androidtv.widget

import android.content.Context
import org.json.JSONObject
import org.moonfin.androidtv.R

/**
 * Les trois widgets, repris de l'app de suivi que Sid utilisait avant
 * (captures du 24.11). Le 4e qu'elle avait, « À voir – Films », a été
 * écarté : « laisse tomber, c'est pas tellement utile ».
 */
enum class WidgetKind(val path: String, val titleRes: Int) {
    /** "9-1-1 / S10E01 That Sinking Feeling / 6 épisodes non vus" */
    CONTINUE_WATCHING("continue-watching", R.string.patoune_widget_next_title) {
        override fun detail(context: Context, item: JSONObject): String? {
            val unwatched = item.optInt("unwatchedCount", 0)
            if (unwatched <= 0) return null
            return context.resources.getQuantityString(
                R.plurals.patoune_widget_unwatched, unwatched, unwatched,
            )
        }
    },

    /** "9-1-1 / S10E07 Old Wounds / 08/01/2027 – dans 45 jours" */
    UPCOMING("upcoming", R.string.patoune_widget_upcoming_title) {
        override fun detail(context: Context, item: JSONObject): String? =
            WidgetDates.describe(context, item.optString("airDate"))
    },

    /** "Yellowjackets / S04E01 Hivemind / 23/11/2026 – il y a 1 jour" */
    RECENTLY_AIRED("recently-aired", R.string.patoune_widget_recent_title) {
        override fun detail(context: Context, item: JSONObject): String? =
            WidgetDates.describe(context, item.optString("airDate"))
    };

    abstract fun detail(context: Context, item: JSONObject): String?
}

package org.moonfin.androidtv.widget

import android.content.Context
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import org.moonfin.androidtv.R

/**
 * "08/01/2027 – dans 45 jours" / "23/11/2026 – il y a 1 jour", comme dans
 * l'ancienne app. Le serveur renvoie une date de calendrier (YYYY-MM-DD)
 * sans heure : l'ancienne app affichait aussi un horaire, que Patoune TV
 * ne stocke pas. Écart assumé, à revoir si ça manque à Sid.
 */
object WidgetDates {
    private val DISPLAY = DateTimeFormatter.ofPattern("dd/MM/yyyy")

    fun describe(context: Context, raw: String?): String? {
        val date = parse(raw) ?: return null
        val days = ChronoUnit.DAYS.between(LocalDate.now(), date)
        val relative = when {
            days == 0L -> context.getString(R.string.patoune_widget_today)
            days > 0 -> context.resources.getQuantityString(
                R.plurals.patoune_widget_in_days, days.toInt(), days.toInt(),
            )
            else -> context.resources.getQuantityString(
                R.plurals.patoune_widget_days_ago, (-days).toInt(), (-days).toInt(),
            )
        }
        return "${date.format(DISPLAY)} – $relative"
    }

    private fun parse(raw: String?): LocalDate? {
        if (raw.isNullOrBlank() || raw == "null") return null
        // Tolère une date seule comme un horodatage complet, selon ce que
        // la route renvoie pour un film ou un épisode.
        return runCatching { LocalDate.parse(raw.take(10)) }.getOrNull()
    }
}

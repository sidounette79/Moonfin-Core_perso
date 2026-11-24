package org.moonfin.androidtv.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import org.moonfin.androidtv.R

/**
 * 24.11, Sid — widgets d'écran d'accueil reprenant ceux de son ancienne
 * app de suivi. Saveur mobile uniquement : ce fichier vit dans
 * app/src/mobile, donc la version Android TV ne l'embarque pas.
 *
 * Trois widgets, une seule implémentation : seul le WidgetKind change.
 * Chaque sous-classe existe parce qu'Android identifie un widget par sa
 * classe — il n'y a pas moyen d'en déclarer trois à partir d'une seule.
 */
abstract class SeriesWidgetProvider : AppWidgetProvider() {

    abstract val kind: WidgetKind

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.patoune_widget)
            views.setTextViewText(R.id.patoune_widget_title, context.getString(kind.titleRes))

            // Chaque instance a besoin d'un Intent distinct, sinon Android
            // réutilise la même RemoteViewsFactory pour les trois widgets
            // (il compare les Intent sans tenir compte des extras).
            val serviceIntent = Intent(context, SeriesWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                putExtra(SeriesWidgetService.EXTRA_KIND, kind.name)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.patoune_widget_list, serviceIntent)
            views.setEmptyView(R.id.patoune_widget_list, R.id.patoune_widget_empty)

            // Toucher une ligne ouvre CARBA TV. Un modèle suffit : Android
            // le complète par ligne (ici sans extra, l'app s'ouvre
            // simplement — ouvrir l'épisode exact viendra ensuite).
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { launch ->
                views.setPendingIntentTemplate(
                    R.id.patoune_widget_list,
                    PendingIntent.getActivity(
                        context, 0, launch,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                    ),
                )
            }

            appWidgetManager.updateAppWidget(id, views)
        }
        // Force la relecture des données : sans ça, un widget déjà posé
        // garderait sa liste précédente après une mise à jour.
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.patoune_widget_list)
    }

    companion object {
        /** Appelé depuis Dart quand les identifiants changent. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            listOf(
                NextEpisodesWidgetProvider::class.java,
                UpcomingWidgetProvider::class.java,
                RecentlyAiredWidgetProvider::class.java,
            ).forEach { cls ->
                val ids = manager.getAppWidgetIds(ComponentName(context, cls))
                if (ids.isEmpty()) return@forEach
                context.sendBroadcast(
                    Intent(context, cls).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    },
                )
            }
        }
    }
}

class NextEpisodesWidgetProvider : SeriesWidgetProvider() {
    override val kind = WidgetKind.CONTINUE_WATCHING
}

class UpcomingWidgetProvider : SeriesWidgetProvider() {
    override val kind = WidgetKind.UPCOMING
}

class RecentlyAiredWidgetProvider : SeriesWidgetProvider() {
    override val kind = WidgetKind.RECENTLY_AIRED
}

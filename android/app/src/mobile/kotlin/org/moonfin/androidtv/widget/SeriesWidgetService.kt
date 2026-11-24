package org.moonfin.androidtv.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.moonfin.androidtv.R

/** Alimente la liste d'un widget. Une instance par widget posé. */
class SeriesWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val kind = runCatching {
            WidgetKind.valueOf(intent.getStringExtra(EXTRA_KIND).orEmpty())
        }.getOrDefault(WidgetKind.CONTINUE_WATCHING)
        return SeriesWidgetFactory(applicationContext, kind)
    }

    companion object {
        const val EXTRA_KIND = "org.moonfin.androidtv.widget.KIND"
    }
}

private class SeriesWidgetFactory(
    private val context: Context,
    private val kind: WidgetKind,
) : RemoteViewsService.RemoteViewsFactory {

    private var entries: List<SeriesEntry> = emptyList()

    override fun onCreate() = Unit

    /**
     * Android appelle ceci hors du fil principal et attend qu'il rende la
     * main avant de dessiner : c'est le seul endroit où l'appel réseau est
     * légitime, d'où le choix d'un client synchrone dans PatouneApi.
     */
    override fun onDataSetChanged() {
        entries = PatouneApi.fetch(context, kind)
    }

    override fun onDestroy() {
        entries = emptyList()
    }

    override fun getCount() = entries.size

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.patoune_widget_item)
        // getViewAt peut être appelé sur une liste déjà remplacée entre
        // deux rafraîchissements : mieux vaut une ligne vide qu'un plantage.
        val entry = entries.getOrNull(position)
            ?: return views

        views.setTextViewText(R.id.patoune_item_title, entry.title)
        setOptional(views, R.id.patoune_item_episode, entry.episodeLabel)
        setOptional(views, R.id.patoune_item_detail, entry.detail)
        views.setOnClickFillInIntent(R.id.patoune_item_root, Intent())
        return views
    }

    private fun setOptional(views: RemoteViews, viewId: Int, text: String?) {
        if (text.isNullOrBlank()) {
            views.setViewVisibility(viewId, android.view.View.GONE)
        } else {
            views.setViewVisibility(viewId, android.view.View.VISIBLE)
            views.setTextViewText(viewId, text)
        }
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount() = 1
    override fun getItemId(position: Int) = position.toLong()
    override fun hasStableIds() = false
}

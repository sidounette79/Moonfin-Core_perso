package org.moonfin.nativevideo.subtitle

import kotlin.math.abs

// Kept free of Android and media3 imports so these run under plain JVM tests.

/**
 * The furthest the user can push subtitles either way.
 *
 * 31.10, Sid ("le décalage des sous-titres... j'ai l'impression que ça
 * change rien") - root cause: the Flutter-side slider range was widened to
 * ±300s the same night (delay_limits.dart, "il faut au moins pouvoir avoir
 * 5 minutes"), but this native clamp was never updated to match, so any
 * value past ±5s was silently clamped back down here and never reached the
 * player - a large correction looked like it did nothing because, in
 * effect, it didn't. Mirrors delay_limits.dart's bound exactly.
 */
internal const val MAX_MANUAL_SUBTITLE_DELAY_MS = 300_000L

/**
 * An automatic correction has to move at least this far before the text
 * track is re-selected for it. The adjuster settles to slightly different
 * values across seeks, and re-timing for a few milliseconds would only blink
 * the cue for nothing.
 */
internal const val MIN_AUTO_RETIME_DELTA_US = 50_000L

private const val MIME_MEDIA3_CUES = "application/x-media3-cues"

private val SHIFTED_TEXT_MIMES = setOf(
    MIME_MEDIA3_CUES,
    "application/pgs",
    "application/vobsub",
    "application/dvbsubs",
    "text/x-ssa",
    "application/x-subrip",
    "text/vtt",
    "application/x-mp4-vtt",
    "application/ttml+xml",
)

private val CLOSED_CAPTION_MIMES = setOf(
    "application/cea-608",
    "application/cea-708",
    "application/x-mp4-cea-608",
)

internal fun clampManualDelayMs(delayMs: Long): Long =
    delayMs.coerceIn(-MAX_MANUAL_SUBTITLE_DELAY_MS, MAX_MANUAL_SUBTITLE_DELAY_MS)

/** What a sideloaded track is shifted by: the measured correction plus the user's delay. */
internal fun effectiveOffsetUs(autoOffsetUs: Long, manualDelayMs: Long): Long =
    autoOffsetUs + clampManualDelayMs(manualDelayMs) * 1000L

/**
 * Whether a track muxed into the content follows the subtitle delay.
 *
 * 31.10, Sid ("l'embarquée décale de base... environ 5 secondes") - closed
 * captions used to be excluded on the assumption that they "ride the
 * video's own timeline already". Confirmed wrong for real broadcast
 * recordings: a live captioner/encoder bakes its own multi-second lag
 * behind picture into the CEA-608/708 stream itself (verified against this
 * exact symptom - a constant few-second offset from the very first cue,
 * present on the embedded EIA-608 track and absent on the file's own text
 * subtitle tracks on the same episode). Emby's own client apparently
 * compensates for this; Moonfin's didn't at all. Letting the MANUAL delay
 * reach these tracks is the fix - the auto sidecar correction
 * ([sidecarOffsetUs]) still never touches them, since that mechanism is
 * calibrated for mis-timed external subtitle files, a different problem.
 */
internal fun shiftsEmbeddedFormat(sampleMimeType: String?, codecs: String?): Boolean {
    val mime = sampleMimeType ?: return false
    if (mime == MIME_MEDIA3_CUES) return true
    return mime in SHIFTED_TEXT_MIMES || mime in CLOSED_CAPTION_MIMES
}

/**
 * Whether the text track has to be re-selected so cues already read take
 * the new offset. The user's own change always is, a measured one only when
 * it moved far enough to see.
 */
internal fun shouldRetime(previousEffectiveUs: Long, nextEffectiveUs: Long, manualChanged: Boolean): Boolean =
    manualChanged || abs(nextEffectiveUs - previousEffectiveUs) >= MIN_AUTO_RETIME_DELTA_US

internal enum class SourceTree {
    /** The player builds the source from the media item itself. */
    PLAYER_ITEM,

    /** The app builds the source so subtitle timing can be shifted. */
    CUSTOM_TREE,
}

/**
 * Which way a source is built. Live TV, previews and audio never get the
 * tree, so their playback is untouched by any of this. Video gets it when a
 * sideloaded subtitle exists, when the user has set a delay, or once it is in
 * place for this source, since taking it out again would mean a re-prepare
 * for nothing.
 */
internal fun sourceTreeFor(
    isLive: Boolean,
    isPreview: Boolean,
    mediaType: String,
    externalCount: Int,
    manualDelayMs: Long,
    hasEmbeddedWrapper: Boolean,
): SourceTree {
    if (isLive || isPreview || mediaType == "audio") return SourceTree.PLAYER_ITEM
    if (externalCount > 0 || manualDelayMs != 0L || hasEmbeddedWrapper) return SourceTree.CUSTOM_TREE
    return SourceTree.PLAYER_ITEM
}

/**
 * The merging period prefixes every child track id with the child's index,
 * so the id a sideloaded track was given comes back as "1:10000". Either
 * spelling is that track.
 */
internal fun externalFormatIdMatches(formatId: String?, targetId: String): Boolean =
    formatId != null && (formatId == targetId || formatId.endsWith(":$targetId"))

/** The sync delays event. The subtitle delay stays the user's own value, the correction rides beside it. */
internal fun syncDelaysPayload(
    audioDelayMs: Long,
    subtitleDelayMs: Long,
    subtitleAutoOffsetMs: Long,
): Map<String, Any> = mapOf(
    "event" to "syncDelays",
    "audioDelayMs" to audioDelayMs,
    "subtitleDelayMs" to subtitleDelayMs,
    "subtitleAutoOffsetMs" to subtitleAutoOffsetMs,
)

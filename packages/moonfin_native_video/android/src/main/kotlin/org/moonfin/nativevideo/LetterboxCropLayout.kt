package org.moonfin.nativevideo

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Sizes the full coded surface so a crop rectangle covers or fits the
 * container. Asymmetric bars need TOP|START + offsets, not Gravity.CENTER.
 */
object LetterboxCropLayout {
    data class Bounds(
        val width: Int,
        val height: Int,
        val left: Int,
        val top: Int,
    )

    fun compute(
        containerWidth: Int,
        containerHeight: Int,
        sourceWidth: Float,
        sourceHeight: Float,
        cropX: Float,
        cropY: Float,
        cropW: Float,
        cropH: Float,
        cover: Boolean,
    ): Bounds {
        if (
            containerWidth <= 0 ||
            containerHeight <= 0 ||
            sourceWidth <= 0f ||
            sourceHeight <= 0f ||
            cropW <= 0f ||
            cropH <= 0f
        ) {
            return Bounds(
                width = containerWidth.coerceAtLeast(1),
                height = containerHeight.coerceAtLeast(1),
                left = 0,
                top = 0,
            )
        }

        val containerAspect = containerWidth.toFloat() / containerHeight.toFloat()
        val cropAspect = cropW / cropH
        // 03.11, same sur-zoom bug as Media3VideoView's ZoomMode.CROP (see
        // its comment) - a portrait container against a landscape crop
        // rectangle would zoom by whatever multiple the two aspects differ
        // by instead of the few-percent "cover" this is meant for. Falls
        // back to the "fit" branch below past that same 2.0x cap.
        val coverZoomRatio = max(containerAspect, cropAspect) / min(containerAspect, cropAspect)
        val effectiveCover = cover && coverZoomRatio <= 2.0f
        val (targetW, targetH) = if (effectiveCover) {
            if (containerAspect > cropAspect) {
                val width = containerWidth.toFloat()
                width to (width / cropAspect)
            } else {
                val height = containerHeight.toFloat()
                (height * cropAspect) to height
            }
        } else {
            if (containerAspect > cropAspect) {
                val height = containerHeight.toFloat()
                (height * cropAspect) to height
            } else {
                val width = containerWidth.toFloat()
                width to (width / cropAspect)
            }
        }

        val scale = targetW / cropW
        val viewW = (sourceWidth * scale).roundToInt().coerceAtLeast(1)
        val viewH = (sourceHeight * scale).roundToInt().coerceAtLeast(1)
        val targetLeft = (containerWidth - targetW) / 2f
        val targetTop = (containerHeight - targetH) / 2f
        return Bounds(
            width = viewW,
            height = viewH,
            left = (targetLeft - cropX * scale).roundToInt(),
            top = (targetTop - cropY * scale).roundToInt(),
        )
    }
}

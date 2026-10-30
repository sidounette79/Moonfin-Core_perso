package org.moonfin.nativevideo

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioPassthroughPolicyTest {

    @Test
    fun `auto allows a bitstream within the known route cap`() {
        val policy = AudioPassthroughPolicy.fromWire(
            "auto",
            emptySet(),
            maxKnownPcmChannels = 2,
        )
        assertTrue(policy.allowsBitstream("audio/ac3", channelCount = 2))
    }

    @Test
    fun `auto vetoes a bitstream wider than the known route cap`() {
        val policy = AudioPassthroughPolicy.fromWire(
            "auto",
            emptySet(),
            maxKnownPcmChannels = 2,
        )
        assertFalse(policy.allowsBitstream("audio/ac3", channelCount = 6))
    }

    @Test
    fun `auto defers to the platform probe with no known cap`() {
        val policy = AudioPassthroughPolicy.fromWire("auto", emptySet())
        assertTrue(policy.allowsBitstream("audio/ac3", channelCount = 6))
    }

    @Test
    fun `auto is unaffected for a format that is not passthrough audio`() {
        val policy = AudioPassthroughPolicy.fromWire(
            "auto",
            emptySet(),
            maxKnownPcmChannels = 2,
        )
        assertTrue(policy.allowsBitstream("audio/mp4a-latm", channelCount = 6))
    }

    @Test
    fun `manual still requires the codec toggle and respects the known cap`() {
        val enabled = AudioPassthroughPolicy.fromWire(
            "manual",
            setOf("ac3"),
            maxKnownPcmChannels = 2,
        )
        assertTrue(enabled.allowsBitstream("audio/ac3", channelCount = 2))
        assertFalse(enabled.allowsBitstream("audio/ac3", channelCount = 6))

        val disabled = AudioPassthroughPolicy.fromWire(
            "manual",
            emptySet(),
            maxKnownPcmChannels = 2,
        )
        assertFalse(disabled.allowsBitstream("audio/ac3", channelCount = 2))
    }

    @Test
    fun `disabled vetoes every passthrough codec regardless of channel count`() {
        val policy = AudioPassthroughPolicy.fromWire(
            "disabled",
            AudioPassthroughPolicy.KNOWN_CODECS,
            maxKnownPcmChannels = 8,
        )
        assertFalse(policy.allowsBitstream("audio/ac3", channelCount = 2))
    }
}

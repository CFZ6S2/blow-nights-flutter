package com.blownights.finder.finder

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Rotating advertised id: HMAC-SHA256(key, "bn-finder-v1:<period>") cut to 8 chars, one period every 15 minutes
 * (UTC epoch-aligned). Must stay identical to lib/services/ble_identity.dart, where friends compute the ids to expect.
 */
object BleIdRotation {
    const val PERIOD_MS = 15L * 60 * 1000
    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    fun period(nowMs: Long): Long = Math.floorDiv(nowMs, PERIOD_MS)

    fun nextRotationMs(nowMs: Long): Long = (period(nowMs) + 1) * PERIOD_MS

    fun idFor(key: String, period: Long): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        val hash = mac.doFinal("bn-finder-v1:$period".toByteArray(Charsets.UTF_8))
        return String(CharArray(FinderBle.ID_LENGTH) { ALPHABET[(hash[it].toInt() and 0xFF) % ALPHABET.length] })
    }
}

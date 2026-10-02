package com.blownights.finder.pass

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log

/**
 * Phone-to-phone NFC for an entry ticket or a drink. While a ticket or consumption QR is on screen, this phone answers
 * like an NFC card with the same code the QR shows (lib/services/nfc_pass.dart sets [payload] and clears it when the
 * QR leaves the screen or the app goes to the background). The door and bar scanners of the app (reader mode, IsoDep)
 * send SELECT with [AID] and redeem the answer like a scanned QR.
 */
class PassHceService : HostApduService() {

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        if (!isSelect(commandApdu)) return SW_NOT_FOUND
        val code = payload ?: run {
            Log.d(TAG, "SELECT received but no ticket or drink on screen")
            return SW_NOT_FOUND
        }
        Log.d(TAG, "pass handed over")
        onHandedOver?.invoke()
        return code.toByteArray(Charsets.UTF_8) + SW_OK
    }

    override fun onDeactivated(reason: Int) {
        Log.d(TAG, "deactivated ($reason)")
    }

    private fun isSelect(apdu: ByteArray): Boolean {
        // CLA INS P1 P2 Lc AID...
        if (apdu.size < 5 + AID.size) return false
        if (apdu[0] != 0x00.toByte() || apdu[1] != 0xA4.toByte() || apdu[2] != 0x04.toByte()) return false
        if (apdu[4].toInt() != AID.size) return false
        return apdu.copyOfRange(5, 5 + AID.size).contentEquals(AID)
    }

    companion object {
        private const val TAG = "BNPassHce"
        /** Proprietary AID: F0 + "BNPASS". Must match res/xml/pass_aid.xml and lib/services/nfc_pass.dart. */
        val AID = byteArrayOf(0xF0.toByte(), 0x42, 0x4E, 0x50, 0x41, 0x53, 0x53)
        private val SW_OK = byteArrayOf(0x90.toByte(), 0x00)
        private val SW_NOT_FOUND = byteArrayOf(0x6A.toByte(), 0x82.toByte())

        /** The code on screen; null means this phone ignores readers. */
        @Volatile var payload: String? = null

        /** Set by MainActivity: tells the screen showing the code that a scanner read it. */
        @Volatile var onHandedOver: (() -> Unit)? = null
    }
}

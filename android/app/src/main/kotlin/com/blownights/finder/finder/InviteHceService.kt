package com.blownights.finder.finder

import android.nfc.cardemulation.HostApduService
import android.os.Bundle

/**
 * Phone-to-phone NFC invite. While the inviter's group screen is showing its invite, this phone answers like an
 * NFC card; the joiner's phone (nfc_manager reader session, IsoDep) sends SELECT with [AID] and gets the payload.
 * Android Beam, which the prototype relied on, was removed in Android 10.
 */
class InviteHceService : HostApduService() {

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        val armed = payload ?: return SW_NOT_FOUND
        if (!isSelectOurAid(commandApdu)) return SW_NOT_FOUND
        return armed.toByteArray(Charsets.UTF_8) + SW_OK
    }

    override fun onDeactivated(reason: Int) {}

    private fun isSelectOurAid(apdu: ByteArray): Boolean {
        // CLA INS P1 P2 Lc AID...
        if (apdu.size < 5 + AID.size) return false
        if (apdu[0] != 0x00.toByte() || apdu[1] != 0xA4.toByte() || apdu[2] != 0x04.toByte()) return false
        if (apdu[4].toInt() != AID.size) return false
        return apdu.copyOfRange(5, 5 + AID.size).contentEquals(AID)
    }

    companion object {
        /** Proprietary AID: F0 + "BNFRIND". Must match res/xml/finder_invite_aid.xml and lib/services/finder_native.dart. */
        val AID = byteArrayOf(0xF0.toByte(), 0x42, 0x4E, 0x46, 0x52, 0x49, 0x4E, 0x44)
        private val SW_OK = byteArrayOf(0x90.toByte(), 0x00)
        private val SW_NOT_FOUND = byteArrayOf(0x6A.toByte(), 0x82.toByte())

        /** Set only while the invite is on screen; null means this phone ignores readers. */
        @Volatile var payload: String? = null
    }
}

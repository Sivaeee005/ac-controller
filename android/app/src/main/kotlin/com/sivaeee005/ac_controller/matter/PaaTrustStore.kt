package com.sivaeee005.ac_controller.matter

import android.content.Context
import android.util.Log
import chip.devicecontroller.AttestationTrustStoreDelegate
import chip.devicecontroller.DeviceAttestation

/**
 * Trusts the production Product Attestation Authority (PAA) root certificates
 * published in the CSA Distributed Compliance Ledger. The DER files are copied
 * into assets/paa at build time from connectedhomeip
 * credentials/production/paa-root-certs (public certificates, no secrets).
 */
class PaaTrustStore(context: Context) : AttestationTrustStoreDelegate {
  private val certs: List<Pair<ByteArray, ByteArray>> = load(context)

  val size: Int
    get() = certs.size

  override fun getProductAttestationAuthorityCert(skid: ByteArray): ByteArray? =
    certs.firstOrNull { (certSkid, _) -> certSkid.contentEquals(skid) }?.second

  private fun load(context: Context): List<Pair<ByteArray, ByteArray>> {
    val names = context.assets.list(DIR)?.filter { it.endsWith(".der") } ?: emptyList()
    val result =
      names.mapNotNull { name ->
        try {
          val der = context.assets.open("$DIR/$name").use { it.readBytes() }
          val skid = DeviceAttestation.extractSkidFromPaaCert(der) ?: return@mapNotNull null
          skid to der
        } catch (e: Exception) {
          Log.w(TAG, "Skipping PAA $name: ${e.message}")
          null
        }
      }
    Log.i(TAG, "Loaded ${result.size} PAA certificates")
    return result
  }

  companion object {
    private const val TAG = "PaaTrustStore"
    private const val DIR = "paa"
  }
}

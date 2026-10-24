/*
 * Adapted from the connectedhomeip CHIPTool example (BluetoothManager.kt).
 * Copyright (c) 2020-2023 Project CHIP Authors. Licensed under the Apache
 * License, Version 2.0: http://www.apache.org/licenses/LICENSE-2.0
 * Changes: callback-based API without coroutines, scan timeout handling,
 * explicit error reporting.
 */
package com.sivaeee005.ac_controller.matter

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import chip.platform.AndroidChipPlatform
import chip.platform.BleCallback
import java.util.UUID

/** Finds the AC over Bluetooth LE by its Matter discriminator and opens a GATT link. */
@SuppressLint("MissingPermission") // Permissions are checked by MainActivity before use.
class BleConnector(private val context: Context, private val platform: AndroidChipPlatform) :
  BleCallback {

  private val main = Handler(Looper.getMainLooper())
  private var gatt: BluetoothGatt? = null
  var connectionId = 0
    private set

  fun isBluetoothOn(): Boolean {
    val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    return manager.adapter?.isEnabled == true
  }

  /** A Matter commissionable BLE advertisement (service 0xFFF6, opcode 0). */
  data class MatterAdvert(val discriminator: Int, val vendorId: Int, val productId: Int)

  /** What the scan saw, for diagnosis when the AC is not found. */
  class ScanReport(
    val device: BluetoothDevice?,
    val devicesSeen: Int,
    val matterAdverts: List<MatterAdvert>,
    val scanError: Int?,
  )

  /**
   * Scans for up to [timeoutMs] and matches the discriminator in software.
   *
   * No hardware ScanFilter is used: some phones (seen on Samsung) return no
   * results at all for service-data filters with a mask.
   */
  fun scan(
    longDiscriminator: Int,
    isShortDiscriminator: Boolean,
    timeoutMs: Long,
    onProgress: (devicesSeen: Int, matterSeen: Int) -> Unit,
    onResult: (ScanReport) -> Unit
  ) {
    val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    val scanner = manager.adapter?.bluetoothLeScanner
    if (scanner == null) {
      onResult(ScanReport(null, 0, emptyList(), -1))
      return
    }
    val seen = HashSet<String>()
    val adverts = LinkedHashMap<String, MatterAdvert>()
    var done = false

    fun finish(device: BluetoothDevice?, error: Int?) {
      if (done) return
      done = true
      try {
        scanner.stopScan(callbackHolder[0])
      } catch (e: Exception) {
        Log.w(TAG, "stopScan", e)
      }
      val report = ScanReport(device, seen.size, adverts.values.toList(), error)
      main.post { onResult(report) }
    }

    val callback =
      object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
          if (done) return
          val address = result.device.address
          val isNew = seen.add(address)
          val data = result.scanRecord?.getServiceData(MATTER_SERVICE)
          val advert = parseAdvert(data)
          if (advert != null) adverts[address] = advert
          if (isNew || advert != null) main.post { onProgress(seen.size, adverts.size) }
          if (advert != null && matches(advert, longDiscriminator, isShortDiscriminator)) {
            finish(result.device, null)
          }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
          results.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
        }

        override fun onScanFailed(errorCode: Int) {
          Log.e(TAG, "BLE scan failed: $errorCode")
          finish(null, errorCode)
        }
      }
    callbackHolder[0] = callback
    val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
    scanner.startScan(emptyList<ScanFilter>(), settings, callback)
    main.postDelayed({ finish(null, null) }, timeoutMs)
  }

  private val callbackHolder = arrayOfNulls<ScanCallback>(1)

  private fun parseAdvert(data: ByteArray?): MatterAdvert? {
    // Matter BLE service data: opcode(1) | discriminator+version(2, LE) | VID(2) | PID(2) | ...
    if (data == null || data.size < 3 || data[0].toInt() != 0) return null
    val dv = (data[1].toInt() and 0xff) or ((data[2].toInt() and 0xff) shl 8)
    val vid = if (data.size >= 5) (data[3].toInt() and 0xff) or ((data[4].toInt() and 0xff) shl 8) else -1
    val pid = if (data.size >= 7) (data[5].toInt() and 0xff) or ((data[6].toInt() and 0xff) shl 8) else -1
    return MatterAdvert(dv and 0xfff, vid, pid)
  }

  private fun matches(a: MatterAdvert, longDiscriminator: Int, isShort: Boolean): Boolean =
    if (isShort) (a.discriminator shr 8) == (longDiscriminator shr 8)
    else a.discriminator == longDiscriminator

  /** Connects, discovers services and sets the MTU; then calls [onReady] with the GATT. */
  fun connect(device: BluetoothDevice, onReady: (BluetoothGatt?) -> Unit) {
    val ble = platform.bleManager
    val wrapped = ble.callback
    var finished = false
    val callback =
      object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt?, status: Int, newState: Int) {
          wrapped.onConnectionStateChange(g, status, newState)
          if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
            g?.discoverServices()
          } else if (newState == BluetoothProfile.STATE_DISCONNECTED && !finished) {
            finished = true
            main.post { onReady(null) }
          }
        }

        override fun onServicesDiscovered(g: BluetoothGatt?, status: Int) {
          wrapped.onServicesDiscovered(g, status)
          g?.requestMtu(247)
        }

        override fun onMtuChanged(g: BluetoothGatt?, mtu: Int, status: Int) {
          wrapped.onMtuChanged(g, mtu, status)
          if (!finished) {
            finished = true
            main.post { onReady(g) }
          }
        }

        @Deprecated("Deprecated in Android 13 but still called on older versions")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
          wrapped.onCharacteristicChanged(g, c)
        }

        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, s: Int) {
          wrapped.onCharacteristicRead(g, c, s)
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, s: Int) {
          wrapped.onCharacteristicWrite(g, c, s)
        }

        override fun onDescriptorRead(g: BluetoothGatt, d: BluetoothGattDescriptor, s: Int) {
          wrapped.onDescriptorRead(g, d, s)
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, s: Int) {
          wrapped.onDescriptorWrite(g, d, s)
        }
      }
    gatt = device.connectGatt(context, false, callback)
    connectionId = ble.addConnection(gatt)
    ble.setBleCallback(this)
  }

  fun close() {
    gatt?.disconnect()
    gatt?.close()
    gatt = null
    connectionId = 0
  }

  override fun onCloseBleComplete(connId: Int) {
    connectionId = 0
  }

  override fun onNotifyChipConnectionClosed(connId: Int) {
    gatt?.close()
    gatt = null
    connectionId = 0
  }

  companion object {
    private const val TAG = "BleConnector"
    private val MATTER_SERVICE = ParcelUuid(UUID.fromString("0000FFF6-0000-1000-8000-00805F9B34FB"))
  }
}

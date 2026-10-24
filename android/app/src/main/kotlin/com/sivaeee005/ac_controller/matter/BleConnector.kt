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

  /** Scans for up to [timeoutMs]; calls [onResult] once with the device or null. */
  fun scan(
    discriminator: Int,
    isShortDiscriminator: Boolean,
    timeoutMs: Long,
    onResult: (BluetoothDevice?) -> Unit
  ) {
    val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    val scanner = manager.adapter?.bluetoothLeScanner
    if (scanner == null) {
      onResult(null)
      return
    }
    var done = false
    val callback =
      object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
          if (done) return
          done = true
          scanner.stopScan(this)
          main.post { onResult(result.device) }
        }

        override fun onScanFailed(errorCode: Int) {
          Log.e(TAG, "BLE scan failed: $errorCode")
          if (done) return
          done = true
          main.post { onResult(null) }
        }
      }
    val versionDiscriminator = discriminator and 0xfff
    val serviceData =
      byteArrayOf(0, versionDiscriminator.toByte(), (versionDiscriminator shr 8).toByte())
    val mask = byteArrayOf(0xff.toByte(), if (isShortDiscriminator) 0x00 else 0xff.toByte(), 0xff.toByte())
    val filter =
      ScanFilter.Builder()
        .setServiceData(ParcelUuid(UUID.fromString(MATTER_UUID)), serviceData, mask)
        .build()
    val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
    scanner.startScan(listOf(filter), settings, callback)
    main.postDelayed(
      {
        if (!done) {
          done = true
          scanner.stopScan(callback)
          onResult(null)
        }
      },
      timeoutMs
    )
  }

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
    private const val MATTER_UUID = "0000FFF6-0000-1000-8000-00805F9B34FB"
  }
}

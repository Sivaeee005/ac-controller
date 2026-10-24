package com.sivaeee005.ac_controller

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.sivaeee005.ac_controller.matter.MatterBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private var permissionCallback: ((Boolean) -> Unit)? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    DebugReport.install(applicationContext)
    DebugReport.log("app started")
    val bridge = MatterBridge(applicationContext) { onResult -> requestBluetooth(onResult) }
    val messenger = flutterEngine.dartExecutor.binaryMessenger
    MethodChannel(messenger, "ac_controller/matter").setMethodCallHandler(bridge)
    EventChannel(messenger, "ac_controller/matter/events").setStreamHandler(bridge)
    MethodChannel(messenger, "ac_controller/debug").setMethodCallHandler { call, result ->
      when (call.method) {
        "build" ->
          Thread {
              val report =
                try {
                  DebugReport.build(applicationContext)
                } catch (e: Throwable) {
                  "Could not build report: $e"
                }
              runOnUiThread { result.success(report) }
            }
            .start()
        "share" -> {
          try {
            DebugReport.share(this, call.argument<String>("report") ?: "")
            result.success(null)
          } catch (e: Throwable) {
            result.error("share_failed", e.message, null)
          }
        }
        "clear" -> {
          DebugReport.clear(applicationContext)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun bluetoothPermissions(): Array<String> =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    } else {
      // Before Android 12, BLE scanning requires location permission.
      arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

  private fun requestBluetooth(onResult: (Boolean) -> Unit) {
    val missing =
      bluetoothPermissions().filter {
        ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
      }
    if (missing.isEmpty()) {
      onResult(true)
      return
    }
    permissionCallback = onResult
    ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQUEST_BLUETOOTH)
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == REQUEST_BLUETOOTH) {
      val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
      permissionCallback?.invoke(granted)
      permissionCallback = null
    }
  }

  companion object {
    private const val REQUEST_BLUETOOTH = 41
  }
}

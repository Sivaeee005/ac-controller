package com.sivaeee005.ac_controller.matter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import chip.devicecontroller.ChipDeviceController
import chip.devicecontroller.CommissionParameters
import chip.devicecontroller.ControllerParams
import chip.devicecontroller.GetConnectedDeviceCallbackJni.GetConnectedDeviceCallback
import chip.devicecontroller.InvokeCallback
import chip.devicecontroller.NetworkCredentials
import chip.devicecontroller.ReportCallback
import chip.devicecontroller.ResubscriptionAttemptCallback
import chip.devicecontroller.SubscriptionEstablishedCallback
import chip.devicecontroller.WriteAttributesCallback
import chip.devicecontroller.model.AttributeWriteRequest
import chip.devicecontroller.model.ChipAttributePath
import chip.devicecontroller.model.ChipEventPath
import chip.devicecontroller.model.ChipPathId
import chip.devicecontroller.model.InvokeElement
import chip.devicecontroller.model.NodeState
import chip.devicecontroller.model.Status
import chip.platform.AndroidBleManager
import chip.platform.AndroidChipPlatform
import chip.platform.ChipMdnsCallbackImpl
import chip.platform.DiagnosticDataProviderImpl
import chip.platform.NsdManagerServiceBrowser
import chip.platform.NsdManagerServiceResolver
import chip.platform.PreferencesConfigurationManager
import chip.platform.PreferencesKeyValueStoreManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import matter.onboardingpayload.OnboardingPayload
import matter.onboardingpayload.OnboardingPayloadParser
import matter.tlv.AnonymousTag
import matter.tlv.TlvWriter

/**
 * Flutter <-> Matter SDK bridge. This app is its own Matter controller
 * (its own fabric); no hub or cloud is used.
 *
 * Security: the setup code and Wi-Fi password are passed to the SDK for
 * commissioning only. They are never logged or stored by this class.
 */
class MatterBridge(
  private val context: Context,
  private val permissions: PermissionGate,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

  /** Implemented by MainActivity: asks the user for Bluetooth permissions. */
  fun interface PermissionGate {
    fun requestBluetooth(onResult: (Boolean) -> Unit)
  }

  private val main = Handler(Looper.getMainLooper())
  private val prefs = context.getSharedPreferences("ac_controller_matter", Context.MODE_PRIVATE)
  private var events: EventChannel.EventSink? = null

  private val platform: AndroidChipPlatform by lazy {
    ChipDeviceController.loadJni()
    AndroidChipPlatform(
      AndroidBleManager(context),
      PreferencesKeyValueStoreManager(context),
      PreferencesConfigurationManager(context),
      NsdManagerServiceResolver(context, NsdManagerServiceResolver.NsdManagerResolverAvailState()),
      NsdManagerServiceBrowser(context),
      ChipMdnsCallbackImpl(),
      DiagnosticDataProviderImpl(context),
    )
  }

  private val controller: ChipDeviceController by lazy {
    platform // the platform must exist before the controller
    ChipDeviceController(
        ControllerParams.newBuilder()
          // 0xFFF4 is the Matter test vendor ID used by the CHIPTool sample controller.
          .setControllerVendorId(0xFFF4)
          .setEnableServerInteractions(true)
          .build()
      )
      .also { it.setAttestationTrustStoreDelegate(PaaTrustStore(context)) }
  }

  private var ble: BleConnector? = null
  private var pendingCommission: MethodChannel.Result? = null
  private var attestationDevicePtr: Long = 0
  private var connectedPtr: Long = 0
  private var connectedNode: Long = 0
  private var pendingConnect: MethodChannel.Result? = null

  // ---- Flutter channels ----

  override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
    events = sink
  }

  override fun onCancel(arguments: Any?) {
    events = null
  }

  private fun emit(event: Map<String, Any?>) = main.post { events?.success(event) }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    try {
      when (call.method) {
        "loadPairedDevice" -> result.success(loadPaired())
        "commission" ->
          commission(
            call.argument<String>("setupCode") ?: "",
            call.argument<String>("ssid") ?: "",
            call.argument<String>("password") ?: "",
            result,
          )
        "continueCommissioning" -> {
          val ptr = attestationDevicePtr
          attestationDevicePtr = 0
          if (ptr != 0L) controller.continueCommissioning(ptr, call.argument<Boolean>("ignore") == true)
          result.success(null)
        }
        "connect" -> connect((call.argument<Number>("nodeId") ?: 0).toLong(), result)
        "disconnect" -> {
          disconnect()
          result.success(null)
        }
        "setPower" ->
          invoke(
            call.argument<Int>("endpoint") ?: 1,
            CLUSTER_ON_OFF,
            if (call.argument<Boolean>("on") == true) CMD_ON else CMD_OFF,
            result,
          )
        "writeAttribute" ->
          write(
            call.argument<Int>("endpoint") ?: 1,
            (call.argument<Number>("cluster") ?: 0).toLong(),
            (call.argument<Number>("attribute") ?: 0).toLong(),
            (call.argument<Number>("value") ?: 0).toLong(),
            result,
          )
        "forget" -> forget((call.argument<Number>("nodeId") ?: 0).toLong(), result)
        else -> result.notImplemented()
      }
    } catch (e: Throwable) {
      Log.e(TAG, "${call.method} failed", e)
      result.error("internal", e.message ?: e.javaClass.simpleName, null)
    }
  }

  // ---- Pairing ----

  private fun loadPaired(): Map<String, Any?>? {
    val node = prefs.getLong(KEY_NODE, 0)
    return if (node == 0L) null else mapOf("nodeId" to node, "label" to prefs.getString(KEY_LABEL, null))
  }

  private fun parseCode(code: String): OnboardingPayload {
    val c = code.trim()
    val parser = OnboardingPayloadParser()
    return if (c.startsWith("MT:")) parser.parseQrCode(c)
    else parser.parseManualPairingCode(c.replace("-", "").replace(" ", ""))
  }

  private fun commission(code: String, ssid: String, password: String, result: MethodChannel.Result) {
    if (pendingCommission != null) {
      result.error("busy", "Pairing is already in progress.", null)
      return
    }
    val payload =
      try {
        parseCode(code)
      } catch (e: Exception) {
        result.error("invalid_code", "The setup code is not valid. Check the Matter sticker.", null)
        return
      }
    if (ssid.isBlank()) {
      result.error("no_wifi", "Enter the name of your 2.4 GHz Wi-Fi network.", null)
      return
    }
    permissions.requestBluetooth { granted ->
      if (!granted) {
        result.error("permission", "Bluetooth permission is needed to pair the AC.", null)
        return@requestBluetooth
      }
      val connector = BleConnector(context, platform)
      if (!connector.isBluetoothOn()) {
        result.error("bluetooth_off", "Turn on Bluetooth and try again.", null)
        return@requestBluetooth
      }
      ble = connector
      pendingCommission = result
      stage("Searching for the AC over Bluetooth")
      connector.scan(payload.discriminator, payload.hasShortDiscriminator, SCAN_TIMEOUT_MS) { device ->
        if (device == null) {
          failCommission(
            "not_found",
            "The AC was not found over Bluetooth. Stand near the AC. If it was paired before, " +
              "reset its Wi-Fi/Matter pairing (see the AC manual) and try again.",
          )
          return@scan
        }
        stage("Connecting to the AC")
        connector.connect(device) { gatt ->
          if (gatt == null) {
            failCommission("ble_failed", "Bluetooth connection to the AC failed. Try again.")
            return@connect
          }
          stage("Sending Wi-Fi details and certificates")
          val nodeId = prefs.getLong(KEY_NEXT_NODE, 1L)
          prefs.edit().putLong(KEY_NEXT_NODE, nodeId + 1).apply()
          controller.setCompletionListener(CommissionListener(nodeId))
          controller.setDeviceAttestationDelegate(ATTESTATION_FAILSAFE_SECS) { devicePtr, _, errorCode ->
            if (errorCode == 0L) {
              controller.continueCommissioning(devicePtr, true)
            } else {
              // Let the user decide; see AttestationFailedEvent in Dart.
              attestationDevicePtr = devicePtr
              emit(mapOf("type" to "attestationFailed", "errorCode" to errorCode))
            }
          }
          val params =
            CommissionParameters.Builder()
              .setNetworkCredentials(
                NetworkCredentials.forWiFi(NetworkCredentials.WiFiCredentials(ssid, password))
              )
              .build()
          controller.pairDevice(gatt, connector.connectionId, nodeId, payload.setupPinCode, params)
        }
      }
    }
  }

  private fun stage(text: String) = emit(mapOf("type" to "stage", "stage" to text))

  private fun failCommission(code: String, message: String) {
    ble?.close()
    ble = null
    val r = pendingCommission ?: return
    pendingCommission = null
    main.post { r.error(code, message, null) }
  }

  private inner class CommissionListener(private val nodeId: Long) :
    ChipDeviceController.CompletionListener {
    override fun onConnectDeviceComplete() {}

    override fun onStatusUpdate(status: Int) {}

    override fun onPairingComplete(errorCode: Long) {
      if (errorCode != 0L) failCommission("pairing_failed", "Pairing failed (code $errorCode).")
    }

    override fun onPairingDeleted(errorCode: Long) {}

    override fun onCommissioningComplete(nodeId: Long, errorCode: Long) {
      if (errorCode != 0L) {
        failCommission(
          "commissioning_failed",
          "The AC could not join Wi-Fi or finish pairing (code $errorCode). " +
            "Check that the network is 2.4 GHz and the password is correct.",
        )
        return
      }
      prefs.edit().putLong(KEY_NODE, nodeId).putString(KEY_LABEL, "Panasonic AC").apply()
      ble?.close()
      ble = null
      val r = pendingCommission ?: return
      pendingCommission = null
      main.post { r.success(mapOf("nodeId" to nodeId, "label" to "Panasonic AC")) }
    }

    override fun onReadCommissioningInfo(
      vendorId: Int,
      productId: Int,
      wifiEndpointId: Int,
      threadEndpointId: Int
    ) {}

    override fun onCommissioningStatusUpdate(nodeId: Long, stageName: String?, errorCode: Long) {
      if (stageName != null) stage("Step: $stageName")
    }

    override fun onNotifyChipConnectionClosed() {}

    override fun onCloseBleComplete() {}

    override fun onError(error: Throwable?) {
      failCommission("pairing_error", error?.message ?: "Unknown pairing error.")
    }

    override fun onOpCSRGenerationComplete(csr: ByteArray?) {}

    override fun onICDRegistrationInfoRequired() {}

    override fun onICDRegistrationComplete(
      errorCode: Long,
      icdDeviceInfo: chip.devicecontroller.ICDDeviceInfo?
    ) {}
  }

  // ---- Connection and subscription ----

  private fun connect(nodeId: Long, result: MethodChannel.Result) {
    disconnect()
    pendingConnect = result
    controller.getConnectedDevicePointer(
      nodeId,
      object : GetConnectedDeviceCallback {
        override fun onDeviceConnected(devicePointer: Long) {
          connectedPtr = devicePointer
          connectedNode = nodeId
          subscribe(devicePointer)
        }

        override fun onConnectionFailure(nodeId: Long, error: Exception) {
          Log.w(TAG, "connect failed", error)
          finishConnect(
            "unreachable",
            "The AC could not be reached on your Wi-Fi. Check that the AC is powered and " +
              "that this device is on the same network.",
          )
        }
      },
    )
  }

  private fun finishConnect(code: String?, message: String?) {
    val r = pendingConnect ?: return
    pendingConnect = null
    main.post { if (code == null) r.success(null) else r.error(code, message, null) }
  }

  private fun subscribe(devicePtr: Long) {
    val any = ChipPathId.forWildcard()
    val paths =
      listOf(
        ChipAttributePath.newInstance(any, ChipPathId.forId(CLUSTER_DESCRIPTOR), ChipPathId.forId(1)),
        ChipAttributePath.newInstance(any, ChipPathId.forId(CLUSTER_ON_OFF), ChipPathId.forId(0)),
        ChipAttributePath.newInstance(any, ChipPathId.forId(CLUSTER_THERMOSTAT), any),
        ChipAttributePath.newInstance(any, ChipPathId.forId(CLUSTER_FAN_CONTROL), any),
        ChipAttributePath.newInstance(any, ChipPathId.forId(CLUSTER_TEMP_MEASUREMENT), ChipPathId.forId(0)),
      ) +
        listOf(1L, 2L, 3L, 4L, 10L).map {
          ChipAttributePath.newInstance(0, CLUSTER_BASIC_INFO, it)
        }
    controller.subscribeToPath(
      SubscriptionEstablishedCallback {
        emit(mapOf("type" to "linkUp"))
        finishConnect(null, null)
      },
      ResubscriptionAttemptCallback { cause, nextMs ->
        emit(
          mapOf(
            "type" to "linkDown",
            "reason" to "Connection to the AC was lost (cause $cause). Reconnecting…",
            "retryInMs" to nextMs,
          )
        )
      },
      object : ReportCallback {
        override fun onError(
          attributePath: ChipAttributePath?,
          eventPath: ChipEventPath?,
          e: Exception
        ) {
          if (attributePath != null) {
            // One attribute is not supported; the rest of the report is still valid.
            Log.d(TAG, "Attribute error $attributePath: ${e.message}")
            return
          }
          Log.w(TAG, "Subscription error", e)
          if (pendingConnect != null) {
            finishConnect("subscribe_failed", "Could not read the AC state: ${e.message}")
          } else {
            emit(mapOf("type" to "linkDown", "reason" to "Connection to the AC was lost."))
          }
        }

        override fun onReport(nodeState: NodeState) {
          emit(mapOf("type" to "reports", "reports" to toReports(nodeState)))
        }
      },
      devicePtr,
      paths,
      emptyList<ChipEventPath>(),
      SUB_MIN_INTERVAL_S,
      SUB_MAX_INTERVAL_S,
      false,
      true,
      0,
    )
  }

  private fun toReports(state: NodeState): List<Map<String, Any?>> {
    val out = mutableListOf<Map<String, Any?>>()
    for ((endpoint, ep) in state.endpointStates) {
      for ((cluster, cl) in ep.clusterStates) {
        for ((attribute, attr) in cl.attributeStates) {
          out +=
            mapOf(
              "endpoint" to endpoint,
              "cluster" to cluster,
              "attribute" to attribute,
              "value" to toDart(attr.value),
            )
        }
      }
    }
    return out
  }

  /** Converts SDK values to types the Flutter codec can send. */
  private fun toDart(v: Any?): Any? =
    when (v) {
      null -> null
      is Boolean, is String -> v
      is Float -> v.toDouble()
      is Double -> v
      is Number -> v.toLong()
      is List<*> -> v.map { toDart(it) }
      is ByteArray -> v
      else -> v.toString()
    }

  private fun disconnect() {
    if (connectedNode != 0L) {
      try {
        controller.shutdownSubscriptions(controller.fabricIndex, connectedNode)
      } catch (e: Exception) {
        Log.w(TAG, "shutdownSubscriptions", e)
      }
    }
    connectedPtr = 0
    connectedNode = 0
  }

  // ---- Commands ----

  private fun requireDevice(result: MethodChannel.Result): Long? {
    if (connectedPtr == 0L) {
      result.error("not_connected", "The AC is not connected.", null)
      return null
    }
    return connectedPtr
  }

  private fun invoke(endpoint: Int, cluster: Long, command: Long, result: MethodChannel.Result) {
    val ptr = requireDevice(result) ?: return
    val emptyFields = TlvWriter().startStructure(AnonymousTag).endStructure().getEncoded()
    controller.invoke(
      object : InvokeCallback {
        override fun onError(e: Exception) {
          main.post { result.error("command_failed", "The AC did not accept the command: ${e.message}", null) }
        }

        override fun onResponse(invokeElement: InvokeElement?, successCode: Long) {
          main.post { result.success(null) }
        }
      },
      ptr,
      InvokeElement.newInstance(endpoint, cluster, command, emptyFields, null),
      0,
      IM_TIMEOUT_MS,
    )
  }

  private fun write(
    endpoint: Int,
    cluster: Long,
    attribute: Long,
    value: Long,
    result: MethodChannel.Result
  ) {
    val ptr = requireDevice(result) ?: return
    val writer = TlvWriter()
    // OccupiedCoolingSetpoint is a signed int16; the other written attributes are unsigned.
    if (cluster == CLUSTER_THERMOSTAT && attribute == ATTR_OCCUPIED_COOLING_SETPOINT) {
      writer.put(AnonymousTag, value.toShort())
    } else {
      writer.putUnsigned(AnonymousTag, value)
    }
    var answered = false
    controller.write(
      object : WriteAttributesCallback {
        override fun onError(attributePath: ChipAttributePath?, e: Exception) {
          if (answered) return
          answered = true
          main.post { result.error("write_failed", "The AC did not accept the change: ${e.message}", null) }
        }

        override fun onResponse(attributePath: ChipAttributePath, status: Status) {
          if (answered) return
          answered = true
          if (status.status == Status.Code.Success) {
            main.post { result.success(null) }
          } else {
            main.post {
              result.error("rejected", "The AC rejected the change (${status.status}).", null)
            }
          }
        }
      },
      ptr,
      listOf(AttributeWriteRequest.newInstance(endpoint, cluster, attribute, writer.getEncoded())),
      0,
      IM_TIMEOUT_MS,
    )
  }

  private fun forget(nodeId: Long, result: MethodChannel.Result) {
    disconnect()
    try {
      // Removes this app's fabric from the AC when it is reachable.
      controller.unpairDevice(nodeId)
    } catch (e: Exception) {
      Log.w(TAG, "unpairDevice", e)
    }
    prefs.edit().remove(KEY_NODE).remove(KEY_LABEL).apply()
    result.success(null)
  }

  companion object {
    private const val TAG = "MatterBridge"
    private const val KEY_NODE = "node_id"
    private const val KEY_LABEL = "label"
    private const val KEY_NEXT_NODE = "next_node_id"
    private const val SCAN_TIMEOUT_MS = 20_000L
    private const val ATTESTATION_FAILSAFE_SECS = 600
    private const val SUB_MIN_INTERVAL_S = 0
    private const val SUB_MAX_INTERVAL_S = 60
    private const val IM_TIMEOUT_MS = 10_000

    const val CLUSTER_ON_OFF = 0x0006L
    const val CLUSTER_DESCRIPTOR = 0x001DL
    const val CLUSTER_BASIC_INFO = 0x0028L
    const val CLUSTER_THERMOSTAT = 0x0201L
    const val CLUSTER_FAN_CONTROL = 0x0202L
    const val CLUSTER_TEMP_MEASUREMENT = 0x0402L
    const val ATTR_OCCUPIED_COOLING_SETPOINT = 0x0011L
    const val CMD_OFF = 0x00L
    const val CMD_ON = 0x01L
  }
}

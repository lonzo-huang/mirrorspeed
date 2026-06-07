package com.amneziawg.amneziawg_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.*

// AmneziaWG Android backend — supports AWG packet-level obfuscation.
// Jc/Jmin/Jmax/S1/S2/H1-H4 params in the wgConf are parsed natively by the
// AWG Go backend; no stripping is needed.
import org.amnezia.awg.backend.Backend
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.Tunnel
import org.amnezia.awg.config.Config

import java.io.ByteArrayInputStream
import java.util.Locale

// ── Channel names ──────────────────────────────────────────────────────────
private const val METHOD_CHANNEL = "com.amneziawg.flutter/awgcontrol"
private const val EVENT_CHANNEL  = "com.amneziawg.flutter/awgstage"
private const val VPN_PERMISSION_REQUEST = 10015
private const val TAG = "AWG"

class AmneziawgFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var tunnelName: String

    private val scope = CoroutineScope(Job() + Dispatchers.Main.immediate)
    private val futureBackend = CompletableDeferred<Backend>()
    private var backend: Backend? = null
    private var tunnel: AwgTunnel? = null
    private var config: Config? = null
    private var vpnStageSink: EventChannel.EventSink? = null
    private var havePermission = false
    private var isVpnChecked = false

    private lateinit var context: Context
    private var activity: Activity? = null

    companion object {
        private var currentState = "no_connection"
        fun getStatus() = currentState
    }

    // ── ActivityAware ──────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity as? FlutterActivity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity as? FlutterActivity
        binding.addActivityResultListener(this)
    }
    override fun onDetachedFromActivity() { activity = null }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        havePermission = (requestCode == VPN_PERMISSION_REQUEST) && (resultCode == Activity.RESULT_OK)
        return havePermission
    }

    // ── FlutterPlugin ──────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        eventChannel  = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)

        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                vpnStageSink = sink
                isVpnChecked = false
            }
            override fun onCancel(args: Any?) {
                vpnStageSink = null
                isVpnChecked = false
            }
        })

        // Initialise AWG backend off main thread
        scope.launch(Dispatchers.IO) {
            try {
                backend = GoBackend(context)
                futureBackend.complete(backend!!)
            } catch (e: Throwable) {
                Log.e(TAG, "AWG backend init failed: ${e.message}", e)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        isVpnChecked = false
    }

    // ── Method dispatch ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize"      -> initTunnel(call.argument<String>("localizedDescription").orEmpty(), result)
            "start"           -> startTunnel(call.argument<String>("wgQuickConfig").orEmpty(), result)
            "stop"            -> stopTunnel(result)
            "stage"           -> result.success(getStatus())
            "transfer"        -> getTransfer(result)
            "checkPermission" -> { checkPermission(); result.success(null) }
            else              -> result.notImplemented()
        }
    }

    // ── Private impl ───────────────────────────────────────────────────────

    private fun initTunnel(name: String, result: Result) {
        scope.launch(Dispatchers.IO) {
            if (Tunnel.isNameInvalid(name)) {
                mainResult(result) { it.error("INVALID_NAME", "Invalid tunnel name: $name", null) }
                return@launch
            }
            tunnelName = name
            checkPermission()
            mainResult(result) { it.success(null) }
        }
    }

    private fun startTunnel(wgQuickConfig: String, result: Result) {
        scope.launch(Dispatchers.IO) {
            try {
                if (!havePermission) {
                    checkPermission()
                    throw Exception("Permissions are not given")
                }
                updateStage("prepare")

                // Pass config directly to the AmneziaWG backend.
                // AWG-specific [Interface] keys (Jc/Jmin/Jmax/S1/S2/H1-H4) are
                // parsed natively by org.amnezia.awg — no stripping needed.
                val stream = ByteArrayInputStream(wgQuickConfig.toByteArray())
                config = Config.parse(stream)

                updateStage("connecting")
                futureBackend.await().setState(
                    getOrCreateTunnel(),
                    Tunnel.State.UP,
                    config,
                )
                Log.i(TAG, "AWG tunnel UP")
                mainResult(result) { it.success("") }
            } catch (e: Exception) {
                Log.e(TAG, "startTunnel error: ${e.message}", e)
                updateStage("error")
                mainResult(result) { it.error("START_FAILED", e.message, null) }
            }
        }
    }

    private fun stopTunnel(result: Result) {
        scope.launch(Dispatchers.IO) {
            try {
                updateStage("disconnecting")
                futureBackend.await().setState(
                    getOrCreateTunnel(),
                    Tunnel.State.DOWN,
                    config,
                )
                Log.i(TAG, "AWG tunnel DOWN")
                mainResult(result) { it.success("") }
            } catch (e: Exception) {
                Log.e(TAG, "stopTunnel error: ${e.message}", e)
                mainResult(result) { it.error("STOP_FAILED", e.message, null) }
            }
        }
    }

    // 返回隧道累计流量(rx+tx 字节)，供客户端本地计量。隧道未起或异常返回 -1。
    private fun getTransfer(result: Result) {
        scope.launch(Dispatchers.IO) {
            val total: Long = try {
                val t = tunnel
                val b = backend
                if (t == null || b == null) -1L
                else {
                    val stats = b.getStatistics(t)
                    stats.totalRx() + stats.totalTx()
                }
            } catch (e: Exception) {
                -1L
            }
            mainResult(result) { it.success(total) }
        }
    }

    private fun checkPermission() {
        val intent = GoBackend.VpnService.prepare(activity ?: return)
        if (intent != null) {
            havePermission = false
            activity?.startActivityForResult(intent, VPN_PERMISSION_REQUEST)
        } else {
            havePermission = true
        }
    }

    private fun getOrCreateTunnel(): AwgTunnel {
        if (tunnel == null) {
            tunnel = AwgTunnel(tunnelName) { state ->
                scope.launch(Dispatchers.Main) {
                    when (state) {
                        Tunnel.State.UP   -> updateStage("connected")
                        Tunnel.State.DOWN -> updateStage("disconnected")
                        else              -> updateStage("wait_connection")
                    }
                }
            }
        }
        return tunnel!!
    }

    private fun updateStage(stage: String) {
        scope.launch(Dispatchers.Main) {
            currentState = stage
            vpnStageSink?.success(stage.lowercase(Locale.ROOT))
        }
    }

    private fun mainResult(result: Result, block: (Result) -> Unit) {
        scope.launch(Dispatchers.Main) { block(result) }
    }
}

// ── Tunnel wrapper ─────────────────────────────────────────────────────────

private typealias StateCallback = (Tunnel.State) -> Unit

private class AwgTunnel(
    private val name: String,
    private val onStateChanged: StateCallback? = null,
) : Tunnel {
    override fun getName() = name
    override fun onStateChange(newState: Tunnel.State) { onStateChanged?.invoke(newState) }
}

package com.mirrorspeed.singbox

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * sing-box 引擎插件。对应 Dart 侧 ProxyCoreEngine：
 *   MethodChannel  'mirrorspeed/singbox'        —— init / start / stop / stage / transferRxTx
 *   EventChannel   'mirrorspeed/singbox/stage'  —— 隧道阶段事件
 *
 * start 前需系统 VPN 授权（VpnService.prepare）；首次会弹系统对话框。
 */
class SingboxFlutterPlugin :
    FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, PluginRegistry.ActivityResultListener {

    private lateinit var context: Context
    private lateinit var control: MethodChannel
    private lateinit var stageEvents: EventChannel
    private var activity: Activity? = null

    // 待授权后继续 start 的配置
    private var pendingConfig: String? = null
    private var pendingResult: MethodChannel.Result? = null

    companion object {
        private const val REQ_VPN = 0x51B0
        // 服务把阶段事件推到这里
        @Volatile var stageSink: EventChannel.EventSink? = null
        private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
        fun emitStage(stage: String) {
            // EventSink 必须在主线程调用（拆除在后台线程跑，这里切回主线程）。
            mainHandler.post { stageSink?.success(stage) }
        }
    }

    // ── FlutterPlugin ──────────────────────────────────────────────────────
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        control = MethodChannel(binding.binaryMessenger, "mirrorspeed/singbox")
        control.setMethodCallHandler(this)
        stageEvents = EventChannel(binding.binaryMessenger, "mirrorspeed/singbox/stage")
        stageEvents.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        control.setMethodCallHandler(null)
        stageEvents.setStreamHandler(null)
    }

    // ── ActivityAware（VpnService.prepare 需要 Activity）───────────────────
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onDetachedFromActivity() { activity = null }

    // ── EventChannel ───────────────────────────────────────────────────────
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { stageSink = events }
    override fun onCancel(arguments: Any?) { stageSink = null }

    // ── MethodChannel ──────────────────────────────────────────────────────
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> result.success(null)   // libbox setup 延迟到服务启动时做

            "start" -> {
                val config = call.argument<String>("config")
                if (config == null) { result.error("no_config", "config missing", null); return }
                // 需要 VPN 授权？
                val prepare = VpnService.prepare(context)
                if (prepare != null) {
                    val act = activity
                    if (act == null) { result.error("no_activity", "VPN 授权需要 Activity", null); return }
                    pendingConfig = config
                    pendingResult = result
                    act.startActivityForResult(prepare, REQ_VPN)
                } else {
                    startService(config)
                    result.success(null)
                }
            }

            "stop" -> {
                // 优先直接同步停(在主线程)，确保 sing-box 完全拆除后再返回——否则切到
                // WireGuard 时 sing-box 还没停干净会撞车崩溃。拿不到实例才退回异步 Intent。
                val svc = SingboxVpnService.instance
                if (svc != null) {
                    try { svc.stopNow() } catch (_: Throwable) {}
                } else {
                    context.startService(Intent(context, SingboxVpnService::class.java)
                        .setAction(SingboxVpnService.ACTION_STOP))
                }
                result.success(null)
            }

            "stage" -> result.success(SingboxVpnService.currentStage)

            "transferRxTx" -> result.success(SingboxVpnService.transferRxTx())

            else -> result.notImplemented()
        }
    }

    private fun startService(config: String) {
        val i = Intent(context, SingboxVpnService::class.java)
            .setAction(SingboxVpnService.ACTION_START)
            .putExtra(SingboxVpnService.EXTRA_CONFIG, config)
        context.startForegroundService(i)
    }

    // ── VPN 授权结果 ───────────────────────────────────────────────────────
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_VPN) return false
        val cfg = pendingConfig; val res = pendingResult
        pendingConfig = null; pendingResult = null
        if (resultCode == Activity.RESULT_OK && cfg != null) {
            startService(cfg); res?.success(null)
        } else {
            res?.error("permission_denied", "用户拒绝了 VPN 授权", null)
        }
        return true
    }
}

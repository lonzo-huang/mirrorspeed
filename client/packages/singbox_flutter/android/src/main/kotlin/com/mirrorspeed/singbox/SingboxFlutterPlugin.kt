package com.mirrorspeed.singbox

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * sing-box 引擎插件（主进程）。SingboxVpnService 跑在 :singbox 独立进程，两者靠：
 *   命令(主→服务)：startService/ACTION_START|STOP Intent
 *   状态(服务→主)：ACTION_STAGE 广播 → 这里的 BroadcastReceiver → EventChannel
 * 独立进程隔离了 libbox 与 wireguard-go 两个 Go 运行时，切换引擎不再撞车。
 */
class SingboxFlutterPlugin :
    FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, PluginRegistry.ActivityResultListener {

    private lateinit var context: Context
    private lateinit var control: MethodChannel
    private lateinit var stageEvents: EventChannel
    private var activity: Activity? = null

    private var stageSink: EventChannel.EventSink? = null
    @Volatile private var lastStage: String = "disconnected"
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    // 待授权后继续 start 的配置
    private var pendingConfig: String? = null
    private var pendingResult: MethodChannel.Result? = null

    // 接收 :singbox 进程广播来的状态
    private val stageReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            val s = intent?.getStringExtra(SingboxVpnService.EXTRA_STAGE) ?: return
            lastStage = s
            mainHandler.post { stageSink?.success(s) }
        }
    }

    // ── FlutterPlugin ──────────────────────────────────────────────────────
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        control = MethodChannel(binding.binaryMessenger, "mirrorspeed/singbox")
        control.setMethodCallHandler(this)
        stageEvents = EventChannel(binding.binaryMessenger, "mirrorspeed/singbox/stage")
        stageEvents.setStreamHandler(this)
        val filter = IntentFilter(SingboxVpnService.ACTION_STAGE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(stageReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(stageReceiver, filter)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        control.setMethodCallHandler(null)
        stageEvents.setStreamHandler(null)
        try { context.unregisterReceiver(stageReceiver) } catch (_: Throwable) {}
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
                // 跨进程：发 Intent 给 :singbox 服务停止。阻塞的拆除发生在那个进程，
                // 不影响主进程 UI/WireGuard。
                context.startService(Intent(context, SingboxVpnService::class.java)
                    .setAction(SingboxVpnService.ACTION_STOP))
                result.success(null)
            }

            "stage" -> result.success(lastStage)

            "transferRxTx" -> result.success(listOf(-1L, -1L))

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

    companion object {
        private const val REQ_VPN = 0x51B0
    }
}

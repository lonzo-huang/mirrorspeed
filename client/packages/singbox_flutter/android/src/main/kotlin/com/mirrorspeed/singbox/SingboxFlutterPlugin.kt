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
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.ConnectionEvents

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

    // ── 速率/用量计量：主进程跑一个 libbox CommandClient 连到 :singbox 的 CommandServer，
    //    订阅 StatusMessage(累计上下行字节)。两进程共用 app files 目录下的 command socket。──
    @Volatile private var lastDownTotal: Long = -1L   // 下行累计(rx)
    @Volatile private var lastUpTotal:   Long = -1L   // 上行累计(tx)
    private var statusClient: CommandClient? = null
    private var didSetupMain = false

    private inner class StatusHandler : CommandClientHandler {
        override fun connected() {}
        override fun disconnected(message: String?) { lastDownTotal = -1L; lastUpTotal = -1L }
        override fun clearLogs() {}
        override fun writeLogs(messageList: LogIterator?) {}
        override fun setDefaultLogLevel(level: Int) {}
        override fun writeStatus(message: StatusMessage?) {
            if (message != null) {
                lastDownTotal = message.downlinkTotal; lastUpTotal = message.uplinkTotal
                android.util.Log.d("singbox", "status down=$lastDownTotal up=$lastUpTotal avail=${message.trafficAvailable}")
            }
        }
        override fun writeGroups(message: OutboundGroupIterator?) {}
        override fun writeConnectionEvents(message: ConnectionEvents?) {}
        override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) {}
        override fun updateClashMode(newMode: String?) {}
    }

    private fun ensureStatusClient() {
        Thread {
            try {
                if (!didSetupMain) {
                    val base = context.filesDir.absolutePath
                    Libbox.setup(SetupOptions().apply {
                        basePath = base; workingPath = "$base/work"; tempPath = "$base/temp"
                        fixAndroidStack = false
                    })
                    didSetupMain = true
                }
                if (statusClient != null) return@Thread
                val client = CommandClient(StatusHandler(), CommandClientOptions().apply {
                    addCommand(Libbox.CommandStatus)   // 订阅状态(含累计上下行)
                    statusInterval = 1_000_000_000L    // 1s(纳秒)
                })
                statusClient = client
                // CommandServer 可能还没起好,重试几次。
                var ok = false
                for (i in 0 until 10) {
                    try { client.connect(); ok = true; break } catch (_: Throwable) { Thread.sleep(500) }
                }
                android.util.Log.d("singbox", "status client connect ok=$ok")
            } catch (e: Throwable) {
                android.util.Log.e("singbox", "ensureStatusClient error", e)
            }
        }.start()
    }

    private fun stopStatusClient() {
        try { statusClient?.disconnect() } catch (_: Throwable) {}
        statusClient = null
        lastDownTotal = -1L; lastUpTotal = -1L
    }

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
                    ensureStatusClient()
                    result.success(null)
                }
            }

            "stop" -> {
                // 跨进程：发 Intent 给 :singbox 服务停止。阻塞的拆除发生在那个进程，
                // 不影响主进程 UI/WireGuard。
                android.util.Log.d("singbox", "plugin: stop requested (main proc)")
                try {
                    context.startService(Intent(context, SingboxVpnService::class.java)
                        .setAction(SingboxVpnService.ACTION_STOP))
                } catch (e: Throwable) {
                    // Android 8+ 后台启动服务可能被拦（BackgroundServiceStartNotAllowed）→
                    // 这才是「有时候断不掉」的头号嫌疑：Intent 没送达 :singbox。
                    android.util.Log.e("singbox", "plugin: startService(STOP) FAILED", e)
                }
                stopStatusClient()
                result.success(null)
            }

            "stage" -> result.success(lastStage)

            "transferRxTx" -> result.success(listOf(lastDownTotal, lastUpTotal))

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
            startService(cfg); ensureStatusClient(); res?.success(null)
        } else {
            res?.error("permission_denied", "用户拒绝了 VPN 授权", null)
        }
        return true
    }

    companion object {
        private const val REQ_VPN = 0x51B0
    }
}

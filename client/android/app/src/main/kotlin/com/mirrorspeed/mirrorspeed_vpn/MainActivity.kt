package com.mirrorspeed.mirrorspeed_vpn

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val lifecycleChannel = "com.mirrorspeed.app/lifecycle"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, lifecycleChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBackground" -> { moveTaskToBack(true); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }

    // 返回键永远「退到后台」（像按 Home 键），绝不结束 Activity / 断开 VPN。
    // 只有 App 内右上角「退出」键才会主动断开并退出。
    // （清单未启用 enableOnBackInvokedCallback，走传统 onBackPressed 路径，确定性生效。）
    @Suppress("DEPRECATION", "MissingSuperCall")
    override fun onBackPressed() {
        moveTaskToBack(true)
    }
}

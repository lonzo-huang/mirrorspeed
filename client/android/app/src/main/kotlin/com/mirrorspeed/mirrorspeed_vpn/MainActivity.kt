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
                    // 返回键不退出应用，改为退到后台（VPN 隧道保持运行）。
                    "moveToBackground" -> { moveTaskToBack(true); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }
}

package com.mirrorspeed.singbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.TunOptions

/**
 * sing-box 隧道服务。用 libbox 运行完整 sing-box 配置（含 tun 入站），tun 的 fd 由本
 * VpnService 建立后交给 libbox。
 *
 * ⚠️ 实施说明（路 B 首版）：libbox 的 [PlatformInterface] 方法集/签名随 sing-box 版本
 * 变化。本文件按标准 libbox API 写就；首次 `flutter build apk` 的编译报错会精确列出
 * 需要实现/对齐的方法，据此补齐。start/stop/前台通知/tun 建立这些框架部分是稳的。
 */
class SingboxVpnService : VpnService(), PlatformInterface {

    companion object {
        const val ACTION_START = "com.mirrorspeed.singbox.START"
        const val ACTION_STOP  = "com.mirrorspeed.singbox.STOP"
        const val EXTRA_CONFIG = "config"

        private const val CHANNEL_ID = "mirrorspeed_singbox"
        private const val NOTI_ID = 0x51B1

        @Volatile var currentStage: String = "disconnected"
            private set

        // TODO: 用量计量。sing-box 的 rx/tx 需经 Clash API / CommandClient 读取，
        // 首版先返回 [-1,-1]（不计量），跑通后再补。
        fun transferRxTx(): List<Long> = listOf(-1L, -1L)
    }

    private var box: BoxService? = null
    private var tunFd: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> { stopBox(); return START_NOT_STICKY }
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config != null) startBox(config)
            }
        }
        return START_STICKY
    }

    private fun setStage(s: String) {
        currentStage = s
        SingboxFlutterPlugin.emitStage(s)
    }

    private fun startBox(config: String) {
        setStage("connecting")
        startForeground(NOTI_ID, buildNotification())
        try {
            val base = filesDir.absolutePath
            Libbox.setup(base, "$base/work", "$base/temp", false)
            box = Libbox.newService(config, this)
            box!!.start()
            setStage("connected")
        } catch (e: Exception) {
            setStage("disconnected")
            Libbox.writeLogString?.let { /* no-op */ }
            stopSelf()
        }
    }

    private fun stopBox() {
        setStage("disconnecting")
        try { box?.close() } catch (_: Exception) {}
        box = null
        try { tunFd?.close() } catch (_: Exception) {}
        tunFd = null
        setStage("disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopBox()
        super.onDestroy()
    }

    override fun onRevoke() {        // 用户在系统里撤销 VPN 授权
        stopBox()
        super.onRevoke()
    }

    // ── libbox PlatformInterface ───────────────────────────────────────────
    // 用 TunOptions 配置 VpnService.Builder，建立隧道，返回 fd 交给 libbox。
    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("MirrorSpeed")
            .setMTU(options.mtu)

        // IPv4 地址
        val addr = options.inet4Address
        while (addr.hasNext()) {
            val p = addr.next()
            builder.addAddress(p.address, p.prefix)
        }
        // IPv4 路由
        if (options.autoRoute) {
            val routes = options.inet4RouteAddress
            if (routes.hasNext()) {
                while (routes.hasNext()) { val r = routes.next(); builder.addRoute(r.address, r.prefix) }
            } else {
                builder.addRoute("0.0.0.0", 0)
            }
            // DNS
            val dns = options.dnsServerAddress
            if (dns.isNotEmpty()) builder.addDnsServer(dns)
        }

        // 分应用（按包名白/黑名单）—— 供以后应用级分流用；首版不设。
        val fd = builder.establish() ?: throw IllegalStateException("VpnService.establish() 返回 null")
        tunFd = fd
        return fd.fd
    }

    override fun writeLog(message: String?) { /* 可转发到 logcat */ }

    // 以下为 PlatformInterface 的其余方法：首版给安全默认值。若 aar 版本的接口签名不同，
    // 编译器会报错，据此调整。
    override fun useProcFS(): Boolean = false
    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun autoDetectInterfaceControl(fd: Int) {}
    override fun usePlatformDefaultInterfaceMonitor(): Boolean = false
    override fun usePlatformInterfaceGetter(): Boolean = false

    // ── 前台通知 ───────────────────────────────────────────────────────────
    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "MirrorSpeed", NotificationManager.IMPORTANCE_LOW))
            }
        }
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("MirrorSpeed")
            .setContentText("共享节点已连接")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
    }
}

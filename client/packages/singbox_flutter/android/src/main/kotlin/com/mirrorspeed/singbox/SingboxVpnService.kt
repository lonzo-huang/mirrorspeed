package com.mirrorspeed.singbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.Notification as LibboxNotification
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState

/**
 * sing-box 隧道服务。基于新版 libbox 的 CommandServer 架构（无独立 BoxService）：
 *   Libbox.setup(SetupOptions) → CommandServer(handler, platform).start()
 *   → startOrReloadService(config, OverrideOptions)
 * 运行期 libbox 回调本类（PlatformInterface）：openTun 建隧道、autoDetectInterfaceControl
 * 保护出站 socket、startDefaultInterfaceMonitor 感知底层网络。
 */
class SingboxVpnService : VpnService(), PlatformInterface, CommandServerHandler {

    companion object {
        const val ACTION_START = "com.mirrorspeed.singbox.START"
        const val ACTION_STOP  = "com.mirrorspeed.singbox.STOP"
        const val EXTRA_CONFIG = "config"

        private const val CHANNEL_ID = "mirrorspeed_singbox"
        private const val NOTI_ID = 0x51B1

        @Volatile private var didSetup = false

        @Volatile var currentStage: String = "disconnected"
            private set

        // TODO: 用量计量需经 CommandClient 读 StatusMessage；首版不计量。
        fun transferRxTx(): List<Long> = listOf(-1L, -1L)
    }

    private var server: CommandServer? = null
    private var tunFd: ParcelFileDescriptor? = null

    // 默认网络监控
    private var connectivity: ConnectivityManager? = null
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var ifaceListener: InterfaceUpdateListener? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> { stopBox(); return START_NOT_STICKY }
            ACTION_START -> intent.getStringExtra(EXTRA_CONFIG)?.let { startBox(it) }
        }
        // 不用 START_STICKY：避免连接失败后系统把残留的 tun 服务拉活导致全局断网
        return START_NOT_STICKY
    }

    private fun setStage(s: String) {
        currentStage = s
        SingboxFlutterPlugin.emitStage(s)
    }

    private fun startBox(config: String) {
        setStage("connecting")
        startForeground(NOTI_ID, buildNotification())
        try {
            if (!didSetup) {
                val base = filesDir.absolutePath
                Libbox.setup(SetupOptions().apply {
                    basePath = base
                    workingPath = "$base/work"
                    tempPath = "$base/temp"
                    fixAndroidStack = false
                })
                didSetup = true
            }
            // 先校验配置，schema/字段错误在这里就能拿到明确报错
            Libbox.checkConfig(config)
            val srv = CommandServer(this, this)
            srv.start()
            srv.startOrReloadService(config, OverrideOptions())
            server = srv
            setStage("connected")
        } catch (e: Exception) {
            android.util.Log.e("singbox", "start failed", e)
            SingboxFlutterPlugin.emitStage("error: ${e.message}")
            setStage("disconnected")
            stopBox()
        }
    }

    private fun stopBox() {
        setStage("disconnecting")
        try { server?.closeService() } catch (_: Exception) {}
        try { server?.close() } catch (_: Exception) {}
        server = null
        stopDefaultInterfaceMonitorInternal()
        try { tunFd?.close() } catch (_: Exception) {}
        tunFd = null
        setStage("disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() { stopBox(); super.onDestroy() }
    override fun onRevoke() { stopBox(); super.onRevoke() }

    // ── CommandServerHandler ───────────────────────────────────────────────
    override fun getSystemProxyStatus(): SystemProxyStatus =
        SystemProxyStatus().apply { available = false; enabled = false }
    override fun serviceReload() { /* 由 startOrReloadService 触发，交给 libbox 内部处理 */ }
    override fun serviceStop() { stopBox() }
    override fun setSystemProxyEnabled(isEnabled: Boolean) {}
    override fun writeDebugMessage(message: String?) { message?.let { android.util.Log.d("singbox", it) } }

    // ── PlatformInterface：建隧道 ──────────────────────────────────────────
    override fun openTun(options: TunOptions): Int {
        val builder = Builder().setSession("MirrorSpeed").setMtu(options.mtu)

        val a4 = options.inet4Address
        while (a4.hasNext()) { val p = a4.next(); builder.addAddress(p.address(), p.prefix()) }
        val a6 = options.inet6Address
        while (a6.hasNext()) { val p = a6.next(); builder.addAddress(p.address(), p.prefix()) }

        if (options.autoRoute) {
            val r4 = options.inet4RouteAddress
            if (r4.hasNext()) { while (r4.hasNext()) { val r = r4.next(); builder.addRoute(r.address(), r.prefix()) } }
            else builder.addRoute("0.0.0.0", 0)
            val r6 = options.inet6RouteAddress
            if (r6.hasNext()) { while (r6.hasNext()) { val r = r6.next(); builder.addRoute(r.address(), r.prefix()) } }

            try {
                val dns = options.dnsServerAddress?.value
                if (!dns.isNullOrEmpty()) builder.addDnsServer(dns)
            } catch (_: Exception) {}
        }

        val fd = builder.establish() ?: throw IllegalStateException("VpnService.establish() 返回 null")
        tunFd = fd
        return fd.fd
    }

    // ── PlatformInterface：socket 保护 + 默认网络监控 ──────────────────────
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    override fun autoDetectInterfaceControl(fd: Int) { protect(fd) }

    // 默认网络监控：sing-box 的 auto_detect_interface 依赖它，否则出站会报
    // "no available network interface"（DNS/代理全失败）。之前疑似它崩溃，真凶是
    // findConnectionOwner 返回 null（已修）；这里恢复正常实现。
    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        ifaceListener = listener
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        connectivity = cm
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = pushDefault(network)
            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) = pushDefault(network, lp)
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = pushDefault(network, caps = caps)
            override fun onLost(network: Network) {
                try { ifaceListener?.updateDefaultInterface("", -1, false, false) } catch (_: Throwable) {}
            }
        }
        netCallback = cb
        try { cm.registerDefaultNetworkCallback(cb) } catch (_: Exception) {}
        // 立即推一次当前默认网络（回调可能不会马上触发）
        try { cm.activeNetwork?.let { pushDefault(it) } } catch (_: Exception) {}
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {
        stopDefaultInterfaceMonitorInternal()
    }

    private fun stopDefaultInterfaceMonitorInternal() {
        val cb = netCallback ?: return
        try { connectivity?.unregisterNetworkCallback(cb) } catch (_: Exception) {}
        netCallback = null
        ifaceListener = null
    }

    private fun pushDefault(
        network: Network,
        lp: LinkProperties? = null,
        caps: NetworkCapabilities? = null,
    ) {
        val listener = ifaceListener ?: return
        val cm = connectivity ?: return
        val name = (lp ?: cm.getLinkProperties(network))?.interfaceName ?: return
        val c = caps ?: cm.getNetworkCapabilities(network)
        val metered = c?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
        val index = try { java.net.NetworkInterface.getByName(name)?.index ?: 0 } catch (_: Exception) { 0 }
        try { listener.updateDefaultInterface(name, index, metered, false) } catch (_: Throwable) {}
    }

    // ── PlatformInterface：其余（安全默认 / 最小实现）──────────────────────
    override fun useProcFS(): Boolean = false
    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun clearDNSCache() {}
    override fun readWIFIState(): WIFIState? = null
    override fun localDNSTransport(): io.nekohasekai.libbox.LocalDNSTransport? = null
    override fun systemCertificates(): StringIterator? = null
    override fun sendNotification(notification: LibboxNotification?) {}
    // sing-box 每条连接 PreMatch 时会调此方法查进程归属。绝不能返回 null——
    // libbox 的 Go 包装层会直接读 owner.UserId，null 会 nil deref 崩溃(service.go:218)。
    // 我们不做按应用分流，返回 userId=-1 的空归属即可（表示未知，不影响路由）。
    override fun findConnectionOwner(
        ipProtocol: Int, sourceAddress: String?, sourcePort: Int,
        destinationAddress: String?, destinationPort: Int,
    ): io.nekohasekai.libbox.ConnectionOwner =
        io.nekohasekai.libbox.ConnectionOwner().apply {
            userId = -1
            userName = ""
            processPath = ""
            setAndroidPackageNames(StringArrayIterator(emptyList()))
        }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val list = try {
            java.net.NetworkInterface.getNetworkInterfaces().toList()
        } catch (_: Exception) { emptyList() }
        val boxed = list.map { ni ->
            LibboxNetworkInterface().apply {
                name = ni.name
                index = try { ni.index } catch (_: Exception) { 0 }
                mtu = try { ni.mtu } catch (_: Exception) { 0 }
                addresses = StringArrayIterator(
                    ni.inetAddresses.toList().mapNotNull { it.hostAddress })
                flags = 0
                type = 0
                dnsServer = StringArrayIterator(emptyList())
                metered = false
            }
        }
        return NetworkInterfaceArrayIterator(boxed)
    }

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

/** libbox StringIterator 的简单实现（从 Kotlin List 提供）。 */
private class StringArrayIterator(items: List<String>) : StringIterator {
    private val it = items.iterator()
    private val size = items.size
    override fun hasNext(): Boolean = it.hasNext()
    override fun next(): String = it.next()
    override fun len(): Int = size
}

/** libbox NetworkInterfaceIterator 的简单实现。 */
private class NetworkInterfaceArrayIterator(items: List<io.nekohasekai.libbox.NetworkInterface>) : NetworkInterfaceIterator {
    private val it = items.iterator()
    override fun hasNext(): Boolean = it.hasNext()
    override fun next(): io.nekohasekai.libbox.NetworkInterface = it.next()
}

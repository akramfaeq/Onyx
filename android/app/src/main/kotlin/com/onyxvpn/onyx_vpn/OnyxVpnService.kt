package com.onyxvpn.onyx_vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import java.io.File
import android.net.VpnService
import android.net.TrafficStats
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import android.util.Base64
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import java.net.InetSocketAddress
import java.net.Inet6Address
import java.net.NetworkInterface as JavaNetworkInterface
import java.security.KeyStore
import androidx.core.app.NotificationCompat
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.libbox.ConnectionOwner
import com.hiddify.core.libbox.LocalDNSTransport
import com.hiddify.core.mobile.Mobile
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.libbox.TunOptions
import com.hiddify.core.libbox.InterfaceUpdateListener
import com.hiddify.core.libbox.NetworkInterfaceIterator
import com.hiddify.core.libbox.NetworkInterface
import com.hiddify.core.libbox.StringIterator
import com.hiddify.core.libbox.WIFIState
import com.hiddify.core.libbox.Notification as CoreNotification
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.ConcurrentHashMap

class OnyxVpnService : VpnService(), PlatformInterface {

    companion object {
        const val TAG          = "OnyxVpnService"
        const val ACTION_START = "com.onyxvpn.START"
        const val ACTION_STOP  = "com.onyxvpn.STOP"
        const val EXTRA_WARP_OVER_PROXY = "warp_over_proxy"
        const val NOTIF_ID     = 100
        const val CHANNEL_ID   = "onyx_vpn"

        @Volatile var instance: OnyxVpnService? = null
        @Volatile var isRunning = false
        val starting = AtomicBoolean(false)
    }

    private val scope  = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val vpnOperationMutex = Mutex()
    private var tunFd: ParcelFileDescriptor? = null
    private var lastRxBytes = -1L
    private var lastTxBytes = -1L
    private var lastStatsAt = 0L
    private val interfaceCallbacks = ConcurrentHashMap<InterfaceUpdateListener, ConnectivityManager.NetworkCallback>()

    // ─── Lifecycle ────────────────────────────────────────────
    override fun onCreate() {
        super.onCreate()
        instance = this
        OnyxCore.init(this)
        createNotificationChannel()
        Log.d(TAG, "service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> { scope.launch { stopVpn() }; return START_NOT_STICKY }
            else        -> scope.launch { startVpn(intent?.getBooleanExtra(EXTRA_WARP_OVER_PROXY, false) ?: false) }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        interfaceCallbacks.keys.toList().forEach { closeDefaultInterfaceMonitor(it) }
        instance = null
        scope.cancel()
        runBlocking { stopVpn() }
        OnyxCore.closeAll()
        super.onDestroy()
    }

    override fun onRevoke() { scope.launch { stopVpn() } }
    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    fun stopAndWait(onComplete: () -> Unit) {
        CoroutineScope(Dispatchers.IO).launch {
            stopVpn()
            withContext(Dispatchers.Main) { onComplete() }
        }
    }

    // ─── Start / Stop ─────────────────────────────────────────
    private suspend fun startVpn(warpOverProxy: Boolean) = withContext(Dispatchers.IO) {
        vpnOperationMutex.withLock {
            if (isRunning || !starting.compareAndSet(false, true)) return@withContext
            try {
                showNotification("Connecting...", "OnyxVPN is starting")

                // Mobile.start() calls openTun() asynchronously via PlatformInterface.
                // We poll until openTun() sets tunFd (max 10 seconds).
                OnyxCore.startCore(this@OnyxVpnService, warpOverProxy)

                val deadline = System.currentTimeMillis() + 10_000L
                while (tunFd == null && System.currentTimeMillis() < deadline) {
                    delay(100)
                }

                if (tunFd == null) {
                    throw IllegalStateException("Core started but TUN interface was not established within 10s")
                }

                lastRxBytes = TrafficStats.getUidRxBytes(android.os.Process.myUid())
                lastTxBytes = TrafficStats.getUidTxBytes(android.os.Process.myUid())
                lastStatsAt = android.os.SystemClock.elapsedRealtime()

                isRunning = true
                showNotification("Connected", "OnyxVPN is active — tap to disconnect")
                Log.d(TAG, "VPN started ✅")
                OnyxChannel.sendStatus("connected")

            } catch (e: Exception) {
                Log.e(TAG, "startVpn error: ${e.message}")
                OnyxChannel.sendStatus("failed:${e.message}")
                runCatching { OnyxCore.stopCore() }
                tunFd?.close()
                tunFd = null
                isRunning = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            } finally {
                starting.set(false)
            }
        }
    }

    private suspend fun stopVpn() = withContext(Dispatchers.IO) {
        vpnOperationMutex.withLock {
            try { OnyxCore.stopCore() }
            catch (e: Exception) { Log.w(TAG, "stop error: " + e.message) }

            tunFd?.close()
            tunFd    = null
            isRunning = false
            starting.set(false)

            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
            stopForeground(STOP_FOREGROUND_REMOVE)

            delay(150)
            OnyxChannel.sendStatus("disconnected")
            Log.d(TAG, "VPN stopped")
        }
    }

    // ─── Stats ────────────────────────────────────────────────
    @Synchronized
    fun queryStats(): Pair<Long, Long> {
        val now = android.os.SystemClock.elapsedRealtime()
        val rx = TrafficStats.getUidRxBytes(android.os.Process.myUid())
        val tx = TrafficStats.getUidTxBytes(android.os.Process.myUid())
        if (rx < 0 || tx < 0 || lastRxBytes < 0 || lastTxBytes < 0 || lastStatsAt == 0L) {
            lastRxBytes = rx; lastTxBytes = tx; lastStatsAt = now
            return Pair(0L, 0L)
        }
        val elapsed = (now - lastStatsAt).coerceAtLeast(1L)
        val down = ((rx - lastRxBytes).coerceAtLeast(0L) * 1000L) / elapsed
        val up   = ((tx - lastTxBytes).coerceAtLeast(0L) * 1000L) / elapsed
        lastRxBytes = rx; lastTxBytes = tx; lastStatsAt = now
        return Pair(down, up)
    }

    // ═══════════════════════════════════════════════════════════
    // PlatformInterface — hiddify-core v5
    // ═══════════════════════════════════════════════════════════

    override fun autoDetectInterfaceControl(fd: Int) { protect(fd) }

    // ── TUN ──────────────────────────────────────────────────
    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("OnyxVPN")
            .setMtu(options.getMTU())  // v5: getMTU()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        // IPv4 addresses — v5: getInet4Address()
        val v4 = options.getInet4Address()
        while (v4.hasNext()) { val a = v4.next(); builder.addAddress(a.address(), a.prefix()) }

        // IPv6 addresses — v5: getInet6Address()
        val v6 = options.getInet6Address()
        while (v6.hasNext()) { val a = v6.next(); builder.addAddress(a.address(), a.prefix()) }

        // Routes — v5: getAutoRoute(), getInet4RouteAddress(), getInet6RouteAddress()
        if (options.getAutoRoute()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val r4 = options.getInet4RouteAddress()
                var hasIpv4Route = false
                while (r4.hasNext()) {
                    val address = r4.next()
                    builder.addRoute(address.address(), address.prefix())
                    hasIpv4Route = true
                }
                if (!hasIpv4Route) builder.addRoute("0.0.0.0", 0)

                val r6 = options.getInet6RouteAddress()
                var hasIpv6Route = false
                while (r6.hasNext()) {
                    val address = r6.next()
                    builder.addRoute(address.address(), address.prefix())
                    hasIpv6Route = true
                }
                if (!hasIpv6Route) builder.addRoute("::", 0)
            } else {
                builder.addRoute("0.0.0.0", 0)
                builder.addRoute("::", 0)
            }
        }

        // DNS — v5: getDNSServerAddress() returns StringIterator (not StringBox)
        val dnsIter = options.getDNSServerAddress()
        while (dnsIter.hasNext()) {
            val dns = dnsIter.next()
            if (dns.isNotBlank()) builder.addDnsServer(dns)
        }

        // Per-app routing — v5: getIncludePackage(), getExcludePackage()
        val includedPackages = options.getIncludePackage()
        var hasIncludedPackages = false
        while (includedPackages.hasNext()) {
            val selectedPackage = includedPackages.next()
            if (selectedPackage != this@OnyxVpnService.packageName) {
                runCatching { builder.addAllowedApplication(selectedPackage) }
            }
            hasIncludedPackages = true
        }
        if (!hasIncludedPackages) {
            val excluded = options.getExcludePackage()
            while (excluded.hasNext()) {
                runCatching { builder.addDisallowedApplication(excluded.next()) }
            }
            runCatching { builder.addDisallowedApplication(this@OnyxVpnService.packageName) }
        }

        val pfd = builder.establish() ?: error("VPN establish failed")
        tunFd = pfd
        return pfd.fd
    }

    fun closeTun() { tunFd?.close(); tunFd = null }

    override fun underNetworkExtension() = false
    override fun usePlatformAutoDetectInterfaceControl() = true
    override fun useProcFS() = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
    override fun includeAllNetworks() = false

    // ── Connection owner — v5: no androidPackageName field; use setAndroidPackageNames() ──
    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int
    ): ConnectionOwner {
        val uid = runCatching {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return@runCatching -1
            val connectivity = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivity.getConnectionOwnerUid(
                ipProtocol,
                InetSocketAddress(sourceAddress, sourcePort),
                InetSocketAddress(destinationAddress, destinationPort)
            )
        }.getOrDefault(-1)
        val app = if (uid >= 0) packageManager.getPackagesForUid(uid)?.firstOrNull().orEmpty() else ""
        return ConnectionOwner().also {
            it.userId   = uid
            it.userName = app
            // v5: setAndroidPackageNames() replaces the removed androidPackageName field
            it.setAndroidPackageNames(StringValues(if (app.isNotEmpty()) listOf(app) else emptyList()))
        }
    }

    override fun sendNotification(n: CoreNotification?) {}
    override fun clearDNSCache() {}

    // ── Interface monitor ─────────────────────────────────────
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val callback = interfaceCallbacks.remove(listener) ?: return
        val connectivity = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        runCatching { connectivity.unregisterNetworkCallback(callback) }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val connectivity = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        interfaceCallbacks.remove(listener)?.let { old ->
            runCatching { connectivity.unregisterNetworkCallback(old) }
        }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = publishDefaultInterface(connectivity, listener)
            override fun onLost(network: Network)      = publishDefaultInterface(connectivity, listener)
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
                publishDefaultInterface(connectivity, listener)
            override fun onLinkPropertiesChanged(network: Network, linkProperties: android.net.LinkProperties) =
                publishDefaultInterface(connectivity, listener)
        }
        interfaceCallbacks[listener] = callback
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            connectivity.registerDefaultNetworkCallback(callback)
        } else {
            connectivity.registerNetworkCallback(
                NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),
                callback
            )
        }
        publishDefaultInterface(connectivity, listener)
    }

    private fun publishDefaultInterface(
        connectivity: ConnectivityManager,
        listener: InterfaceUpdateListener
    ) {
        val network      = connectivity.activeNetwork
        val properties   = network?.let { connectivity.getLinkProperties(it) }
        val capabilities = network?.let { connectivity.getNetworkCapabilities(it) }
        val name  = properties?.interfaceName.orEmpty()
        val index = runCatching { JavaNetworkInterface.getByName(name)?.index ?: -1 }.getOrDefault(-1)
        val metered = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true
        listener.updateDefaultInterface(name, index, metered, false)
    }

    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun systemCertificates(): StringIterator {
        val certificates = mutableListOf<String>()
        runCatching {
            val keyStore = KeyStore.getInstance("AndroidCAStore")
            keyStore.load(null, null)
            val aliases = keyStore.aliases()
            while (aliases.hasMoreElements()) {
                val certificate = keyStore.getCertificate(aliases.nextElement()) ?: continue
                val encoded = Base64.encodeToString(certificate.encoded, Base64.NO_WRAP)
                certificates.add("-----BEGIN CERTIFICATE-----\n" + encoded + "\n-----END CERTIFICATE-----")
            }
        }.onFailure { Log.w(TAG, "Unable to load system certificates: " + it.message) }
        return StringValues(certificates)
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val interfaces   = mutableListOf<NetworkInterface>()
        val connectivity = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        val networkDetails = mutableMapOf<String, Pair<List<String>, NetworkCapabilities?>>()
        runCatching {
            connectivity.allNetworks.forEach { network ->
                val properties = connectivity.getLinkProperties(network) ?: return@forEach
                val name = properties.interfaceName ?: return@forEach
                val dns  = properties.dnsServers.map { it.hostAddress.orEmpty().substringBefore('%') }
                    .filter { it.isNotBlank() }
                networkDetails[name] = dns to connectivity.getNetworkCapabilities(network)
            }
        }
        val available = JavaNetworkInterface.getNetworkInterfaces()
        while (available != null && available.hasMoreElements()) {
            val systemInterface = available.nextElement()
            val boxInterface    = NetworkInterface()
            boxInterface.name  = systemInterface.name
            boxInterface.index = systemInterface.index
            boxInterface.mtu   = runCatching { systemInterface.mtu }.getOrDefault(1500)
            val capabilities   = networkDetails[systemInterface.name]?.second
            boxInterface.type  = when {
                capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)     == true -> Libbox.InterfaceTypeWIFI
                capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true -> Libbox.InterfaceTypeCellular
                capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true -> Libbox.InterfaceTypeEthernet
                systemInterface.name.startsWith("wlan")  -> Libbox.InterfaceTypeWIFI
                systemInterface.name.startsWith("rmnet") -> Libbox.InterfaceTypeCellular
                systemInterface.name.startsWith("eth")   -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            boxInterface.flags   = if (systemInterface.isUp) 0x1 or 0x40 else 0
            boxInterface.metered = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true
            val addresses = systemInterface.interfaceAddresses.mapNotNull { item ->
                val address = item.address
                val host = if (address is Inet6Address)
                    address.hostAddress.substringBefore('%')
                else
                    address.hostAddress
                if (host.isNullOrBlank()) null else "$host/" + item.networkPrefixLength
            }
            boxInterface.addresses  = StringValues(addresses)
            boxInterface.dnsServer  = StringValues(networkDetails[systemInterface.name]?.first.orEmpty())
            interfaces.add(boxInterface)
        }
        return NetworkInterfaces(interfaces.iterator())
    }

    override fun readWIFIState(): WIFIState? = null

    // ── v5 new abstract stubs — features not needed by OnyxVPN ───────────────

    /** Tailscale hostname — not used */
    override fun tailscaleHostname(): String = ""

    /** Whether to use platform auto-redirect (Tailscale/TUN-based) — false = use sing-box built-in */
    override fun usePlatformAutoRedirect(): Boolean = false

    /** Whether to use platform bridge — false = not implemented */
    override fun usePlatformBridge(): Boolean = false

    /** Whether to use platform shell — false = not implemented */
    override fun usePlatformShell(): Boolean = false

    /** Create auto-redirect session — not used (usePlatformAutoRedirect=false) */
    override fun createAutoRedirect(
        options: ByteArray?,
        handler: com.hiddify.core.libbox.AutoRedirectHandler?
    ): com.hiddify.core.libbox.AutoRedirectSession? = null

    /** Create bridge session — not used (usePlatformBridge=false) */
    override fun createBridge(
        options: com.hiddify.core.libbox.BridgeOptions?
    ): com.hiddify.core.libbox.BridgeSession? = null

    /** Open shell session — not used (usePlatformShell=false) */
    override fun openShellSession(
        user: com.hiddify.core.libbox.PlatformUser?,
        command: String?,
        environ: StringIterator?,
        term: String?,
        rows: Int,
        cols: Int
    ): com.hiddify.core.libbox.ShellSession? = null

    /** Check platform shell availability — no-op */
    override fun checkPlatformShell() {}

    /** Look up SFTP server — not used */
    override fun lookupSFTPServer(): com.hiddify.core.libbox.StringBox? = null

    /** Look up platform user — not used */
    override fun lookupUser(username: String?): com.hiddify.core.libbox.PlatformUser? = null

    /** Read system SSH host key — not used */
    override fun readSystemSSHHostKey(): com.hiddify.core.libbox.StringBox? = null

    /** Register network interface name — no-op */
    override fun registerMyInterface(name: String?) {}

    /** Cancel notification by identifier — no-op (we manage our own notifications) */
    override fun cancelNotification(identifier: String?, typeID: Int) {}

    /** Start neighbor monitor — no-op (not needed on Android) */
    override fun startNeighborMonitor(
        listener: com.hiddify.core.libbox.NeighborUpdateListener?
    ) {}

    /** Close neighbor monitor — no-op */
    override fun closeNeighborMonitor(
        listener: com.hiddify.core.libbox.NeighborUpdateListener?
    ) {}

    // ── Helpers ───────────────────────────────────────────────
    private class StringValues(private val values: List<String>) : StringIterator {
        private var index = 0
        override fun hasNext() = index < values.size
        override fun next()    = values[index++]
        override fun len()     = values.size
    }

    private class NetworkInterfaces(private val values: Iterator<NetworkInterface>) : NetworkInterfaceIterator {
        override fun hasNext() = values.hasNext()
        override fun next()    = values.next()
    }

    // ── Notification ──────────────────────────────────────────
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "OnyxVPN Status", NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false); enableVibration(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
    }

    private fun showNotification(title: String, body: String) {
        val stopIntent = PendingIntent.getService(
            this, 0,
            Intent(this, OnyxVpnService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(R.drawable.ic_disconnect, "Disconnect", stopIntent)
            .build()

        startForeground(NOTIF_ID, notif)
    }
}

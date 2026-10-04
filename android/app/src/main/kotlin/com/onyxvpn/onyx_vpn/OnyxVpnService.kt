package com.onyxvpn.onyx_vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.libbox.TunOptions
import com.hiddify.core.libbox.Notification as CoreNotification
import kotlinx.coroutines.*

class OnyxVpnService : VpnService(), PlatformInterface {

    companion object {
        const val TAG          = "OnyxVpnService"
        const val ACTION_START = "com.onyxvpn.START"
        const val ACTION_STOP  = "com.onyxvpn.STOP"
        const val NOTIF_ID     = 100
        const val CHANNEL_ID   = "onyx_vpn"

        @Volatile var instance: OnyxVpnService? = null
        @Volatile var isRunning = false
    }

    private val scope  = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var tunFd: ParcelFileDescriptor? = null
    private var serviceBox: com.hiddify.core.libbox.BoxService? = null

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
            else        -> scope.launch { startVpn() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        scope.cancel()
        runBlocking { stopVpn() }
        super.onDestroy()
    }

    override fun onRevoke() { scope.launch { stopVpn() } }
    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    // ─── Start / Stop ─────────────────────────────────────────
    private suspend fun startVpn() = withContext(Dispatchers.IO) {
        try {
            showNotification("Connecting...", "OnyxVPN is starting")

            serviceBox = Libbox.newService(
                OnyxCore.configPath,
                this@OnyxVpnService,
                false
            )
            serviceBox?.start()

            isRunning = true
            showNotification("Connected", "OnyxVPN is active — tap to disconnect")
            Log.d(TAG, "VPN started ✅")
            OnyxChannel.sendStatus("connected")

        } catch (e: Exception) {
            Log.e(TAG, "startVpn error: ${e.message}")
            OnyxChannel.sendStatus("failed:${e.message}")
            stopSelf()
        }
    }

    private suspend fun stopVpn() = withContext(Dispatchers.IO) {
        try { serviceBox?.close(); serviceBox = null }
        catch (e: Exception) { Log.w(TAG, "stop error: ${e.message}") }

        tunFd?.close(); tunFd = null
        isRunning = false

        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
        OnyxChannel.sendStatus("disconnected")
        stopSelf()
        Log.d(TAG, "VPN stopped")
    }

    // ─── Stats — يُرسل لـ Flutter كل ثانية ──────────────────
    fun queryStats(): Pair<Long, Long> {
        return try {
            val stats = serviceBox?.queryStats()
            if (stats != null) Pair(stats.downlink, stats.uplink)
            else Pair(0L, 0L)
        } catch (_: Exception) {
            Pair(0L, 0L)
        }
    }

    // ─── PlatformInterface ────────────────────────────────────
    override fun autoDetectInterfaceControl(fd: Int) { protect(fd) }

    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("OnyxVPN")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        // IPv4
        val v4 = options.inet4Address
        while (v4.hasNext()) { val a = v4.next(); builder.addAddress(a.address(), a.prefix()) }

        // IPv6
        val v6 = options.inet6Address
        while (v6.hasNext()) { val a = v6.next(); builder.addAddress(a.address(), a.prefix()) }

        // Routes
        if (options.autoRoute) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val r4 = options.inet4RouteAddress
                if (r4.hasNext()) while (r4.hasNext()) { val a = r4.next(); builder.addRoute(a.address(), a.prefix()) }
                else builder.addRoute("0.0.0.0", 0)

                val r6 = options.inet6RouteAddress
                if (r6.hasNext()) while (r6.hasNext()) { val a = r6.next(); builder.addRoute(a.address(), a.prefix()) }
                else builder.addRoute("::", 0)
            } else {
                builder.addRoute("0.0.0.0", 0)
                builder.addRoute("::", 0)
            }
        }

        // Excluded packages
        try {
            val excluded = options.excludePackage
            if (excluded != null) {
                while (excluded.hasNext()) {
                    val pkg = excluded.next()
                    try { builder.addDisallowedApplication(pkg) }
                    catch (e: Exception) { Log.w(TAG, "exclude $pkg failed: ${e.message}") }
                }
            }
        } catch (_: Exception) {}

        // دائماً استثني التطبيق نفسه
        builder.addDisallowedApplication(packageName)

        // DNS
        if (options.dnsMode.value != Libbox.DNSModeDisabled) {
            val dns = options.dnsServerAddress
            while (dns.hasNext()) builder.addDnsServer(dns.next())
        }

        val pfd = builder.establish() ?: error("VPN establish failed")
        tunFd = pfd
        return pfd.fd
    }

    override fun closeTun() { tunFd?.close(); tunFd = null }

    override fun usePlatformDefaultInterfaceMonitor() = true
    override fun includeAllNetworks()                  = false

    override fun findConnectionOwner(p0: Int, p1: String?, p2: Int, p3: String?, p4: Int): String = ""

    override fun packageNameByUid(uid: Int): String {
        return try { packageManager.getNameForUid(uid) ?: "" }
        catch (_: Exception) { "" }
    }

    override fun sendNotification(n: CoreNotification?) {}
    override fun cancelNotification(id: String?, typeId: Int) {}

    // ─── Notification ─────────────────────────────────────────
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

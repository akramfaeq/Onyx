package com.onyxvpn.onyx_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class VpnNotificationService : Service() {

    companion object {
        // ─── FIX 3: استخدم channel وID مختلف عن مكتبة OpenVPN ───
        // المكتبة تستخدم channel "OpenVPN" وID = 1
        // نحن نستخدم channel مالتنا وID مختلف — بهيج ما صار تداخل
        private const val OUR_CHANNEL_ID       = "OnyxVPN_Status"
        private const val OUR_NOTIFICATION_ID  = 9001  // رقم مختلف عن مكتبة OpenVPN

        const val ACTION_DISCONNECT = "com.onyxvpn.ACTION_DISCONNECT"
        const val ACTION_SHOW       = "com.onyxvpn.ACTION_SHOW"
        const val ACTION_HIDE       = "com.onyxvpn.ACTION_HIDE"

        fun show(context: Context, serverName: String) {
            val intent = Intent(context, VpnNotificationService::class.java).apply {
                action = ACTION_SHOW
                putExtra("server_name", serverName)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun hide(context: Context) {
            val intent = Intent(context, VpnNotificationService::class.java).apply {
                action = ACTION_HIDE
            }
            context.startService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureOurChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {

            ACTION_SHOW -> {
                val serverName = intent.getStringExtra("server_name") ?: "VPN"
                val notification = buildNotification(serverName)

                // ─── FIX 3: startForeground فقط — بدون notify ثاني
                // لأن startForeground يعرض الإشعار تلقائياً
                // إضافة notify بنفس الـ ID يصنع إشعارين
                startForeground(OUR_NOTIFICATION_ID, notification)
            }

            ACTION_DISCONNECT -> {
                val disconnectIntent = Intent("com.onyxvpn.DISCONNECT")
                sendBroadcast(disconnectIntent)
                stopForeground(true)
                stopSelf()
            }

            ACTION_HIDE -> {
                stopForeground(true)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(serverName: String): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val disconnectIntent = PendingIntent.getService(
            this, 1,
            Intent(this, VpnNotificationService::class.java).apply {
                action = ACTION_DISCONNECT
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, OUR_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("OnyxVPN Connected")
            .setContentText("🌐 $serverName")
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setColor(0xFF7B5CF0.toInt())
            .setColorized(true)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Disconnect",
                disconnectIntent
            )
            .build()
    }

    // ─── FIX 3: channel مالتنا منفصل — ما يتداخل مع مكتبة OpenVPN
    private fun ensureOurChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(OUR_CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    OUR_CHANNEL_ID,
                    "OnyxVPN Status",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "VPN connection status"
                    setShowBadge(false)
                    enableLights(false)
                    enableVibration(false)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }
}

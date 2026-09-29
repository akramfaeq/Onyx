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
        const val CHANNEL_ID      = "OnyxVPN_Status"
        const val NOTIFICATION_ID = 9001

        const val ACTION_SHOW       = "com.onyxvpn.ACTION_SHOW"
        const val ACTION_HIDE       = "com.onyxvpn.ACTION_HIDE"
        const val ACTION_DISCONNECT = "com.onyxvpn.DISCONNECT"

        fun show(context: Context, serverName: String, ping: Int = -1) {
            val intent = Intent(context, VpnNotificationService::class.java).apply {
                action = ACTION_SHOW
                putExtra("server_name", serverName)
                putExtra("ping", ping)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun hide(context: Context) {
            try {
                context.startService(
                    Intent(context, VpnNotificationService::class.java).apply {
                        action = ACTION_HIDE
                    }
                )
            } catch (_: Exception) {}
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        // لازم نسوي startForeground فوراً عشان Android 8+ ما يكرهنا
        startForeground(NOTIFICATION_ID, buildNotification("Connecting...", -1))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val serverName = intent.getStringExtra("server_name") ?: "VPN"
                val ping = intent.getIntExtra("ping", -1)
                // حدّث الـ notification بمعلومات الاتصال
                val nm = getSystemService(NotificationManager::class.java)
                nm.notify(NOTIFICATION_ID, buildNotification(serverName, ping))
            }
            ACTION_HIDE -> {
                stopForeground(true)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(serverName: String, ping: Int): Notification {
        // فتح التطبيق عند الضغط على الإشعار
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // زر Disconnect — يرسل broadcast للـ MainActivity
        val disconnectIntent = PendingIntent.getBroadcast(
            this, 1,
            Intent(ACTION_DISCONNECT).apply {
                `package` = packageName // مهم لـ Android 14+
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val pingText = if (ping in 1..998) " · ${ping}ms" else ""

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_vpn_notification)
            .setContentTitle("🔒 OnyxVPN — Connected")
            .setContentText("$serverName$pingText")
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setColor(0xFF7B5CF0.toInt())
            .setColorized(true)
            .addAction(
                NotificationCompat.Action.Builder(
                    R.drawable.ic_disconnect,
                    "Disconnect",
                    disconnectIntent
                ).build()
            )
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "OnyxVPN Status",
                        NotificationManager.IMPORTANCE_LOW
                    ).apply {
                        description = "VPN connection status"
                        setShowBadge(false)
                        enableLights(false)
                        enableVibration(false)
                    }
                )
            }
        }
    }
}

package com.onyxvpn.onyx_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class VpnNotificationService : Service() {

    companion object {
        const val CHANNEL_ID      = "OnyxVPN_Status"
        const val NOTIFICATION_ID = 9001

        const val ACTION_SHOW       = "com.onyxvpn.ACTION_SHOW"
        const val ACTION_HIDE       = "com.onyxvpn.ACTION_HIDE"
        // ✅ زرنا — يرسل broadcast للـ Flutter بدون dialog
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
            context.startService(
                Intent(context, VpnNotificationService::class.java).apply {
                    action = ACTION_HIDE
                }
            )
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val serverName = intent.getStringExtra("server_name") ?: "VPN"
                val ping = intent.getIntExtra("ping", -1)
                startForeground(NOTIFICATION_ID, buildNotification(serverName, ping))
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

        // ✅ زر Disconnect مالتنا — يرسل broadcast مباشرة للـ Flutter
        // بدون ما يمر على OpenVPN = بدون dialog
        val disconnectIntent = PendingIntent.getBroadcast(
            this, 1,
            Intent(ACTION_DISCONNECT),
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
            // ✅ زر واحد فقط — مالتنا — بدون dialog
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
                val channel = NotificationChannel(
                    CHANNEL_ID,
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

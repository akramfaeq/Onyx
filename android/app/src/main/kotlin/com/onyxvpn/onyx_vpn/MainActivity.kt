package com.onyxvpn.onyx_vpn

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val VPN_PERMISSION_CODE = 1001
        private const val NOTIF_CHANNEL   = "com.onyxvpn.notification"
        private const val V2RAY_CHANNEL   = "com.onyxvpn.v2ray"
    }

    private var notifChannel: MethodChannel? = null
    private var v2rayChannel: MethodChannel? = null

    // يستقبل أمر disconnect من زر الـ notification
    private val disconnectReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            notifChannel?.invokeMethod("disconnect", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ─── Notification Channel ──────────────────────────────
        notifChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIF_CHANNEL
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        val name = call.argument<String>("server_name") ?: "VPN"
                        val ping = call.argument<Int>("ping") ?: -1
                        VpnNotificationService.show(this@MainActivity, name, ping)
                        result.success(null)
                    }
                    "hide" -> {
                        VpnNotificationService.hide(this@MainActivity)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // ─── V2Ray Channel ─────────────────────────────────────
        v2rayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            V2RAY_CHANNEL
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── connect ─────────────────────────────────
                    "connect" -> {
                        val config = call.argument<String>("config") ?: ""
                        val name   = call.argument<String>("name")   ?: "VPN"

                        if (config.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        // طلب إذن VPN لو ما عندنا
                        val intent = VpnService.prepare(this@MainActivity)
                        if (intent != null) {
                            // ما عندنا إذن — طلبه وارجع false
                            startActivityForResult(intent, VPN_PERMISSION_CODE)
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        try {
                            // شغّل V2Ray Service
                            val serviceIntent = Intent(
                                this@MainActivity,
                                V2RayVpnService::class.java
                            ).apply {
                                putExtra("config", config)
                                putExtra("name", name)
                            }
                            startService(serviceIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    // ── disconnect ──────────────────────────────
                    "disconnect" -> {
                        try {
                            val stopIntent = Intent(
                                this@MainActivity,
                                V2RayVpnService::class.java
                            ).apply { action = "STOP" }
                            startService(stopIntent)
                        } catch (_: Exception) {}
                        result.success(null)
                    }

                    // ── status ──────────────────────────────────
                    "status" -> {
                        result.success(V2RayVpnService.isRunning)
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // طلب إذن VPN عند أول فتح
        val vpnIntent = VpnService.prepare(this)
        if (vpnIntent != null) {
            startActivityForResult(vpnIntent, VPN_PERMISSION_CODE)
        }

        // سجّل receiver للـ disconnect من الـ notification
        val filter = IntentFilter("com.onyxvpn.DISCONNECT")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(disconnectReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(disconnectReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(disconnectReceiver) } catch (_: Exception) {}
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_CODE && resultCode == Activity.RESULT_OK) {
            // إذن VPN تم ✅ — المستخدم يضغط connect مرة ثانية
        }
    }
}

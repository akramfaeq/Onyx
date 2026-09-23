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
        private const val CHANNEL = "com.onyxvpn/notification"
    }

    private var methodChannel: MethodChannel? = null

    private val disconnectReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            methodChannel?.invokeMethod("disconnect", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "showNotification" -> {
                        val serverName = call.argument<String>("serverName") ?: "Unknown"
                        VpnNotificationService.show(this@MainActivity, serverName)
                        result.success(null)
                    }
                    "hideNotification" -> {
                        VpnNotificationService.hide(this@MainActivity)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // اطلب إذن VPN عند أول فتح للتطبيق
        val vpnIntent = VpnService.prepare(this)
        if (vpnIntent != null) {
            startActivityForResult(vpnIntent, VPN_PERMISSION_CODE)
        }
        // سجّل receiver هنا بدل onStart — يبقى شغّال حتى لو التطبيق بالخلفية
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
        // ألغِ التسجيل هنا بدل onStop — لا يموت إلا لما يُقتل التطبيق نهائياً
        try { unregisterReceiver(disconnectReceiver) } catch (_: Exception) {}
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_CODE && resultCode == Activity.RESULT_OK) {
            // إذن VPN تم ✅
        }
    }
}

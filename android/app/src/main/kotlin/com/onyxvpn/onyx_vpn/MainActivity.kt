package com.onyxvpn.onyx_vpn

import android.content.Intent
import android.net.VpnService
import android.util.Log
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        const val TAG            = "OnyxMainActivity"
        const val VPN_REQUEST_CODE = 200
        var instance: MainActivity? = null
    }

    private var pendingStart = false
    private var pendingWarpOverProxy = false

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        instance = this
        OnyxCore.init(this)

        // ─── Method Channel ───────────────────────────────────
        val mc = MethodChannel(engine.dartExecutor.binaryMessenger, OnyxChannel.METHOD_CHANNEL)
        OnyxChannel.setMethodChannel(mc)

        mc.setMethodCallHandler { call, result ->
            when (call.method) {

                "setup" -> {
                    val grpcPort = call.argument<Int>("grpcPort") ?: 9090
                    val err = OnyxCore.setup(grpcPort)
                    if (err.isEmpty()) result.success(true)
                    else result.error("SETUP_FAILED", err, null)
                }

                "start" -> {
                    val config = call.argument<String>("config") ?: ""
                    val warpOverProxy = call.argument<Boolean>("warpOverProxy") ?: false
                    if (config.isEmpty()) {
                        result.error("NO_CONFIG", "config is empty", null)
                        return@setMethodCallHandler
                    }

                    // ① اكتب الكونفيغ للملف
                    OnyxCore.writeConfig(config)

                    // ② تحقق من صحة الكونفيغ قبل البدء
                    // Hiddify Core validates its extended configuration types, including Psiphon.
                    // The plain Libbox pre-check can reject extensions before Hiddify Core parses them.

                    // ③ اطلب VPN permission
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        pendingStart = true
                        pendingWarpOverProxy = warpOverProxy
                        OnyxChannel.sendStatus("permission_requested")
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                        result.success("permission_requested")
                    } else {
                        startOnyxService(warpOverProxy)
                        result.success("starting")
                    }
                }

                "stop" -> {
                    stopVpnAndRespond(result)
                }

                "isRunning" -> {
                    result.success(OnyxVpnService.isRunning)
                }

                // Flutter يطلب stats كل ثانية
                "getStats" -> {
                    val svc = OnyxVpnService.instance
                    if (svc != null && OnyxVpnService.isRunning) {
                        val (down, up) = svc.queryStats()
                        result.success(mapOf("down" to down, "up" to up))
                    } else {
                        result.success(mapOf("down" to 0L, "up" to 0L))
                    }
                }

                else -> result.notImplemented()
            }
        }

        // ─── Event Channel (status stream) ────────────────────
        EventChannel(engine.dartExecutor.binaryMessenger, OnyxChannel.EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    OnyxChannel.setEventSink(sink)
                }
                override fun onCancel(args: Any?) {
                    OnyxChannel.setEventSink(null)
                }
            })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == RESULT_OK && pendingStart) {
                startOnyxService(pendingWarpOverProxy)
            } else {
                OnyxChannel.sendStatus("failed:Permission denied by user")
            }
            pendingStart = false
            pendingWarpOverProxy = false
        }
    }
    private fun startOnyxService(warpOverProxy: Boolean) {
        val intent = Intent(this, OnyxVpnService::class.java).apply {
            action = OnyxVpnService.ACTION_START
            putExtra(OnyxVpnService.EXTRA_WARP_OVER_PROXY, warpOverProxy)
        }
        startForegroundService(intent)
    }

    private fun stopVpnAndRespond(result: MethodChannel.Result, attempt: Int = 0) {
        val service = OnyxVpnService.instance
        if (service != null) {
            service.stopAndWait { result.success(true) }
        } else if (attempt < 10) {
            Handler(Looper.getMainLooper()).postDelayed({
                stopVpnAndRespond(result, attempt + 1)
            }, 50)
        } else {
            stopService(Intent(this, OnyxVpnService::class.java))
            result.success(true)
        }
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }
}

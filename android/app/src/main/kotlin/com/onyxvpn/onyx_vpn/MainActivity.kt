package com.onyxvpn.onyx_vpn

import android.content.Intent
import android.net.VpnService
import android.util.Log
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
                    if (config.isEmpty()) {
                        result.error("NO_CONFIG", "config is empty", null)
                        return@setMethodCallHandler
                    }

                    // ① اكتب الكونفيغ للملف
                    OnyxCore.writeConfig(config)

                    // ② تحقق من صحة الكونفيغ قبل البدء
                    val checkErr = OnyxCore.checkConfig(config)
                    if (checkErr.isNotEmpty()) {
                        Log.e(TAG, "Config check failed: $checkErr")
                        result.error("INVALID_CONFIG", checkErr, null)
                        return@setMethodCallHandler
                    }

                    // ③ اطلب VPN permission
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        pendingStart = true
                        OnyxChannel.sendStatus("permission_requested")
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                        result.success("permission_requested")
                    } else {
                        startOnyxService()
                        result.success("starting")
                    }
                }

                "stop" -> {
                    stopService(Intent(this, OnyxVpnService::class.java))
                    result.success(true)
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
                startOnyxService()
            } else {
                OnyxChannel.sendStatus("failed:Permission denied by user")
            }
            pendingStart = false
        }
    }

    private fun startOnyxService() {
        val intent = Intent(this, OnyxVpnService::class.java).apply {
            action = OnyxVpnService.ACTION_START
        }
        startForegroundService(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }
}

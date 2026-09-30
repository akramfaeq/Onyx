package com.onyxvpn.onyx_vpn

import android.content.Intent
import android.net.VpnService
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.ServerSocket
import java.net.URI

class V2RayVpnService : VpnService() {

    companion object {
        var isRunning = false
        private const val TAG = "V2RayVpnService"
        private const val SOCKS_PORT = 10808
    }

    private var xrayProcess: Process? = null
    private var tun2socksProcess: Process? = null
    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            stopAll()
            return START_NOT_STICKY
        }
        val config = intent?.getStringExtra("config") ?: return START_NOT_STICKY
        val name   = intent.getStringExtra("name") ?: "OnyxVPN"
        Thread { startAll(config, name) }.start()
        return START_STICKY
    }

    private fun startAll(rawConfig: String, name: String) {
        try {
            stopAll()

            // 1. حوّل الكونفيغ لـ JSON
            val jsonConfig = parseConfigToJson(rawConfig) ?: run {
                Log.e(TAG, "Failed to parse config: ${rawConfig.take(100)}")
                return
            }
            Log.d(TAG, "Parsed config: ${jsonConfig.take(200)}")

            // 2. انسخ الملفات — دايماً اعد النسخ عشان تتحدث
            val xrayBin      = copyAssetForce("xray").also { it.setExecutable(true) }
            val tun2socksBin = copyAssetForce("tun2socks").also { it.setExecutable(true) }
            copyAssetForce("geoip.dat")
            copyAssetForce("geosite.dat")

            Log.i(TAG, "xray exists: ${xrayBin.exists()}, size: ${xrayBin.length()}")
            Log.i(TAG, "tun2socks exists: ${tun2socksBin.exists()}, size: ${tun2socksBin.length()}")

            // 3. احفظ الـ config
            val configFile = File(filesDir, "xray_config.json")
            configFile.writeText(jsonConfig)

            // 4. شغّل xray
            val xrayCmd = listOf(xrayBin.absolutePath, "run", "-c", configFile.absolutePath)
            Log.i(TAG, "Starting xray: $xrayCmd")

            xrayProcess = ProcessBuilder(xrayCmd)
                .directory(filesDir)
                .redirectErrorStream(true)
                .start()

            // اقرأ output xray فوراً
            val xrayOutput = StringBuilder()
            Thread {
                xrayProcess?.inputStream?.bufferedReader()?.forEachLine { line ->
                    Log.d(TAG, "xray: $line")
                    xrayOutput.appendLine(line)
                }
            }.also { it.isDaemon = true }.start()

            // 5. انتظر xray يبدأ ويفتح الـ port
            var xrayReady = false
            repeat(15) { i ->
                Thread.sleep(500)
                if (isPortOpen(SOCKS_PORT)) {
                    xrayReady = true
                    Log.i(TAG, "✅ xray ready after ${(i+1)*500}ms")
                    return@repeat
                }
                Log.d(TAG, "Waiting for xray... ${(i+1)*500}ms")
            }

            if (!xrayReady) {
                Log.e(TAG, "❌ xray failed to start! Output: $xrayOutput")
                stopAll()
                return
            }

            // 6. أنشئ الـ VPN interface
            vpnInterface = Builder()
                .setSession(name)
                .addAddress("10.0.0.2", 32)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")
                .setMtu(1500)
                .also {
                    try { it.addDisallowedApplication(packageName) } catch (_: Exception) {}
                }
                .establish()

            if (vpnInterface == null) {
                Log.e(TAG, "❌ VPN interface null — no permission?")
                stopAll()
                return
            }

            val tunFd = vpnInterface!!.fd
            Log.i(TAG, "VPN interface fd=$tunFd")

            // 7. شغّل tun2socks
            val tun2socksCmd = listOf(
                tun2socksBin.absolutePath,
                "--device", "fd://$tunFd",
                "--proxy",  "socks5://127.0.0.1:$SOCKS_PORT",
                "--loglevel", "warning"
            )
            Log.i(TAG, "Starting tun2socks: $tun2socksCmd")

            tun2socksProcess = ProcessBuilder(tun2socksCmd)
                .directory(filesDir)
                .redirectErrorStream(true)
                .start()

            Thread {
                tun2socksProcess?.inputStream?.bufferedReader()?.forEachLine { line ->
                    Log.d(TAG, "tun2socks: $line")
                }
            }.also { it.isDaemon = true }.start()

            Thread.sleep(500)

            // تحقق إن tun2socks لا يزال شغّال
            val t2sAlive = tun2socksProcess?.isAlive ?: false
            Log.i(TAG, "tun2socks alive: $t2sAlive")

            isRunning = true
            Log.i(TAG, "✅ VPN started: $name")
            VpnNotificationService.show(this, name, -1)

        } catch (e: Exception) {
            Log.e(TAG, "Error starting VPN: ${e.message}", e)
            stopAll()
        }
    }

    private fun isPortOpen(port: Int): Boolean {
        return try {
            val socket = java.net.Socket()
            socket.connect(java.net.InetSocketAddress("127.0.0.1", port), 300)
            socket.close()
            true
        } catch (_: Exception) { false }
    }

    private fun stopAll() {
        try { tun2socksProcess?.destroy(); tun2socksProcess = null } catch (_: Exception) {}
        try { xrayProcess?.destroy();      xrayProcess      = null } catch (_: Exception) {}
        try { vpnInterface?.close();       vpnInterface     = null } catch (_: Exception) {}
        isRunning = false
        try { VpnNotificationService.hide(this) } catch (_: Exception) {}
        stopSelf()
        Log.i(TAG, "✅ VPN stopped")
    }

    // انسخ دايماً بغض النظر إذا موجود
    private fun copyAssetForce(name: String): File {
        val out = File(filesDir, name)
        try {
            assets.open(name).use { i -> out.outputStream().use { o -> i.copyTo(o) } }
            Log.i(TAG, "Copied asset: $name (${out.length()} bytes)")
        } catch (e: Exception) {
            Log.w(TAG, "Asset not found: $name — ${e.message}")
        }
        return out
    }

    // ─── PARSE CONFIG ─────────────────────────────────────────
    private fun parseConfigToJson(config: String): String? = try {
        when {
            config.startsWith("vmess://")     -> parseVmess(config)
            config.startsWith("vless://")     -> parseVless(config)
            config.startsWith("trojan://")    -> parseTrojan(config)
            config.startsWith("ss://")        -> parseShadowsocks(config)
            config.startsWith("hysteria2://") ||
            config.startsWith("hy2://")       -> parseHysteria2(config)
            else -> null
        }
    } catch (e: Exception) {
        Log.e(TAG, "Parse error: ${e.message}")
        null
    }

    private fun parseVmess(config: String): String {
        val obj = JSONObject(String(Base64.decode(config.removePrefix("vmess://"), Base64.DEFAULT)))
        return buildXrayJson(
            address = obj.optString("add"), port = obj.optInt("port", 443),
            id = obj.optString("id"), protocol = "vmess",
            network = obj.optString("net", "tcp"), tls = obj.optString("tls") == "tls",
            host = obj.optString("host"), path = obj.optString("path"), security = "auto"
        )
    }

    private fun parseVless(config: String): String {
        val uri = URI(config); val params = parseQuery(uri.rawQuery ?: "")
        return buildXrayJson(
            address = uri.host ?: "", port = if (uri.port > 0) uri.port else 443,
            id = uri.userInfo ?: "", protocol = "vless",
            network = params["type"] ?: "tcp",
            tls = (params["security"] ?: "") in listOf("tls", "reality"),
            host = params["sni"] ?: params["host"] ?: "",
            path = params["path"] ?: "", security = "none",
            flow = params["flow"] ?: "", pbk = params["pbk"] ?: "", sid = params["sid"] ?: ""
        )
    }

    private fun parseTrojan(config: String): String {
        val uri = URI(config); val params = parseQuery(uri.rawQuery ?: "")
        return buildXrayJson(
            address = uri.host ?: "", port = if (uri.port > 0) uri.port else 443,
            id = uri.userInfo ?: "", protocol = "trojan",
            network = params["type"] ?: "tcp", tls = true,
            host = params["sni"] ?: uri.host ?: "", path = params["path"] ?: "", security = "none"
        )
    }

    private fun parseShadowsocks(config: String): String {
        val raw = config.removePrefix("ss://")
        val atIdx = raw.lastIndexOf('@')
        val decoded = String(Base64.decode(raw.substring(0, atIdx), Base64.DEFAULT))
        val (method, password) = decoded.split(":", limit = 2)
        val hostPort = raw.substring(atIdx + 1).split("#")[0].split(":")
        return JSONObject().apply {
            put("log", JSONObject().put("loglevel", "warning"))
            put("inbounds", JSONArray().put(socksInbound()))
            put("outbounds", JSONArray().put(JSONObject().apply {
                put("protocol", "shadowsocks")
                put("settings", JSONObject().put("servers", JSONArray().put(JSONObject().apply {
                    put("address", hostPort[0])
                    put("port", hostPort.getOrNull(1)?.toIntOrNull() ?: 443)
                    put("method", method); put("password", password)
                })))
            }))
        }.toString()
    }

    private fun parseHysteria2(config: String): String {
        val uri = URI(config.replace("hy2://", "hysteria2://"))
        val params = parseQuery(uri.rawQuery ?: "")
        return JSONObject().apply {
            put("log", JSONObject().put("loglevel", "warning"))
            put("inbounds", JSONArray().put(socksInbound()))
            put("outbounds", JSONArray().put(JSONObject().apply {
                put("protocol", "hysteria2")
                put("settings", JSONObject().put("servers", JSONArray().put(JSONObject().apply {
                    put("address", uri.host ?: "")
                    put("port", if (uri.port > 0) uri.port else 443)
                    put("password", uri.userInfo ?: "")
                    put("tls", JSONObject().apply {
                        put("enabled", true)
                        put("serverName", params["sni"] ?: uri.host ?: "")
                        put("insecure", params["insecure"] == "1")
                    })
                })))
            }))
        }.toString()
    }

    private fun buildXrayJson(
        address: String, port: Int, id: String, protocol: String,
        network: String = "tcp", tls: Boolean = false,
        host: String = "", path: String = "", security: String = "none",
        flow: String = "", pbk: String = "", sid: String = ""
    ): String {
        val stream = JSONObject().apply {
            put("network", network)
            if (tls) {
                if (pbk.isNotEmpty()) {
                    put("security", "reality")
                    put("realitySettings", JSONObject().apply {
                        put("serverName", host); put("publicKey", pbk)
                        put("shortId", sid); put("fingerprint", "chrome")
                    })
                } else {
                    put("security", "tls")
                    put("tlsSettings", JSONObject().apply {
                        put("serverName", host); put("allowInsecure", false)
                        put("fingerprint", "chrome")
                    })
                }
            }
            when (network) {
                "ws" -> put("wsSettings", JSONObject().apply {
                    put("path", path); put("headers", JSONObject().put("Host", host))
                })
                "grpc" -> put("grpcSettings", JSONObject().put("serviceName", path))
                "h2" -> put("httpSettings", JSONObject().apply {
                    put("host", JSONArray().put(host)); put("path", path)
                })
            }
        }

        val user = JSONObject().apply {
            put(if (protocol == "trojan") "password" else "id", id)
            when (protocol) {
                "vless" -> { put("encryption", "none"); if (flow.isNotEmpty()) put("flow", flow) }
                "vmess" -> { put("alterId", 0); put("security", security) }
            }
        }

        val settingsKey = when (protocol) {
            "trojan", "shadowsocks" -> "servers"
            else -> "vnext"
        }

        return JSONObject().apply {
            put("log", JSONObject().put("loglevel", "warning"))
            put("inbounds", JSONArray().put(socksInbound()))
            put("outbounds", JSONArray().apply {
                put(JSONObject().apply {
                    put("tag", "proxy"); put("protocol", protocol)
                    put("settings", JSONObject().put(settingsKey, JSONArray().put(JSONObject().apply {
                        put("address", address); put("port", port)
                        put("users", JSONArray().put(user))
                    })))
                    put("streamSettings", stream)
                })
                put(JSONObject().apply { put("tag", "direct"); put("protocol", "freedom") })
                put(JSONObject().apply { put("tag", "block"); put("protocol", "blackhole") })
            })
            put("routing", JSONObject().apply {
                put("domainStrategy", "IPIfNonMatch")
                put("rules", JSONArray().apply {
                    put(JSONObject().apply {
                        put("type", "field"); put("outboundTag", "direct")
                        put("ip", JSONArray().apply { put("geoip:private"); put("geoip:ir") })
                    })
                    put(JSONObject().apply {
                        put("type", "field"); put("outboundTag", "direct")
                        put("domain", JSONArray().put("geosite:ir"))
                    })
                })
            })
        }.toString()
    }

    private fun socksInbound() = JSONObject().apply {
        put("port", SOCKS_PORT); put("protocol", "socks")
        put("listen", "127.0.0.1")
        put("settings", JSONObject().apply { put("auth", "noauth"); put("udp", true) })
    }

    private fun parseQuery(query: String): Map<String, String> =
        if (query.isEmpty()) emptyMap()
        else query.split("&").mapNotNull {
            val p = it.split("=", limit = 2)
            if (p.size == 2) p[0] to java.net.URLDecoder.decode(p[1], "UTF-8") else null
        }.toMap()

    override fun onDestroy() { stopAll(); super.onDestroy() }
}

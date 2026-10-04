package com.onyxvpn.onyx_vpn

import android.content.Context
import android.util.Log
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.mobile.Mobile
import com.hiddify.core.mobile.SetupOptions
import java.io.File

/**
 * OnyxCore — واجهة بسيطة لـ hiddify-core native library
 * يهيّئ الـ core ويشغّل/يوقف الـ VPN
 */
object OnyxCore {

    private const val TAG = "OnyxCore"
    private var initialized = false
    private var serviceBox: Any? = null

    // مسارات الملفات
    lateinit var baseDir: String
    lateinit var workingDir: String
    lateinit var tempDir: String
    lateinit var configPath: String

    fun init(context: Context) {
        if (initialized) return
        baseDir    = context.filesDir.path
        workingDir = (context.getExternalFilesDir(null) ?: context.filesDir).path
        tempDir    = context.cacheDir.path
        configPath = "$workingDir/config.json"

        File(baseDir).mkdirs()
        File(workingDir).mkdirs()
        File(tempDir).mkdirs()

        try {
            Libbox.redirectStderr(File(workingDir, "stderr.log").path)
        } catch (e: Exception) {
            Log.w(TAG, "redirectStderr failed: ${e.message}")
        }

        initialized = true
        Log.d(TAG, "OnyxCore initialized — workingDir: $workingDir")
    }

    fun setup(grpcPort: Int): String {
        return try {
            Mobile.setup(
                SetupOptions().also {
                    it.basePath   = baseDir
                    it.workingDir = workingDir
                    it.tempDir    = tempDir
                    it.fixAndroidStack = true
                    it.mode       = 3L   // VPN mode
                    it.listen     = "127.0.0.1:$grpcPort"
                    it.secret     = ""
                    it.debug      = false
                },
                null
            )
            Log.d(TAG, "setup ok — gRPC on $grpcPort")
            ""
        } catch (e: Exception) {
            Log.e(TAG, "setup error: ${e.message}")
            e.message ?: "setup failed"
        }
    }

    fun writeConfig(json: String) {
        File(configPath).writeText(json)
        Log.d(TAG, "config written (${json.length} chars)")
    }

    fun checkConfig(json: String): String {
        return try {
            val tmp = File(tempDir, "check_tmp.json")
            tmp.writeText(json)
            val err = Libbox.checkConfig(tmp.path)
            tmp.delete()
            err ?: ""
        } catch (e: Exception) {
            e.message ?: "check failed"
        }
    }
}

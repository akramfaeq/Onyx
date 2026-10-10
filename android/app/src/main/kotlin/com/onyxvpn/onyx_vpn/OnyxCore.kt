package com.onyxvpn.onyx_vpn

import android.content.Context
import android.util.Log
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.mobile.Mobile
import com.hiddify.core.mobile.SetupOptions
import java.io.File

// ─── OnyxCore — نفس طريقة هايدفاي بدون gRPC ──────────────────────────
// هايدفاي لا يستخدم ChangeHiddifySettings أثناء الاتصال
// الكونفيغ يُكتب على الـ disk كاملاً من Flutter قبل startCore
// warpOverProxy يتحكم به الكونفيغ نفسه (outbound psiphon-out موجود أو لا)
// ─────────────────────────────────────────────────────────────────────

object OnyxCore {
    private const val TAG = "OnyxCore"
    private var initialized = false

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

        runCatching { Libbox.redirectStderr(File(workingDir, "stderr.log").path) }
            .onFailure { Log.w(TAG, "redirectStderr failed: ${it.message}") }

        initialized = true
        Log.d(TAG, "initialized — workingDir=$workingDir")
    }

    fun writeConfig(json: String) {
        File(configPath).writeText(json)
        Log.d(TAG, "config written (${json.length} chars)")
    }

    fun checkConfig(json: String): String = try {
        Libbox.checkConfig(json)
        ""
    } catch (e: Exception) {
        e.message ?: "Invalid configuration"
    }

    // نفس ترتيب هايدفاي: setup ثم start — بدون أي gRPC call
    // warpOverProxy: المعامل يُمرَّر لكن الكونفيغ هو اللي يتحكم فعلياً
    // (Dart تكتب الكونفيغ الصحيح قبل استدعاء startCore)
    fun startCore(platform: PlatformInterface, warpOverProxy: Boolean) {
        Log.d(TAG, "startCore — warpOverProxy=$warpOverProxy")

        Mobile.setup(
            SetupOptions().also {
                it.basePath       = baseDir
                it.workingDir     = workingDir
                it.tempDir        = tempDir
                it.listen         = "127.0.0.1:9090"
                it.secret         = ""
                it.mode           = 4L
                it.fixAndroidStack = true
            },
            platform
        )
        Log.d(TAG, "Mobile.setup done")

        Mobile.start(configPath, "")
        Log.d(TAG, "Mobile.start done ✅")
    }

    fun stopCore() {
        Log.d(TAG, "stopCore")
        try   { Mobile.stop()  }
        catch (e: Exception) { Log.w(TAG, "Mobile.stop error: ${e.message}") }
        try   { Mobile.close(4L) }
        catch (e: Exception) { Log.w(TAG, "Mobile.close error: ${e.message}") }
    }
}

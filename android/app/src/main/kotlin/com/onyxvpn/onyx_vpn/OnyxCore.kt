package com.onyxvpn.onyx_vpn

import android.content.Context
import android.util.Log
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.mobile.Mobile
import com.hiddify.core.mobile.SetupOptions
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

// ─── OnyxCore — نفس طريقة هايدفاي بدون gRPC ──────────────────────────
// الإصلاح الرئيسي:
//   - Mobile.close() يدمر الـ engine نهائياً في العملية الحالية
//   - الحل: نستدعيه مرة واحدة فقط عند إغلاق التطبيق كلياً
//   - للوقف العادي: Mobile.stop() يكفي بدون close()
//   - للبدء من جديد: Mobile.start() بعد Mobile.stop() مباشرة — بدون setup من جديد
// ─────────────────────────────────────────────────────────────────────

object OnyxCore {
    private const val TAG = "OnyxCore"

    private val initialized  = AtomicBoolean(false)
    private val mobileSetup  = AtomicBoolean(false)   // ← جديد: هل Mobile.setup() اتنفذ؟

    lateinit var baseDir:    String
    lateinit var workingDir: String
    lateinit var tempDir:    String
    lateinit var configPath: String

    fun init(context: Context) {
        if (!initialized.compareAndSet(false, true)) return

        baseDir    = context.filesDir.path
        workingDir = (context.getExternalFilesDir(null) ?: context.filesDir).path
        tempDir    = context.cacheDir.path
        configPath = "$workingDir/config.json"

        File(baseDir).mkdirs()
        File(workingDir).mkdirs()
        File(tempDir).mkdirs()

        runCatching { Libbox.redirectStderr(File(workingDir, "stderr.log").path) }
            .onFailure { Log.w(TAG, "redirectStderr failed: ${it.message}") }

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

    // stub — MainActivity يستدعيه لكن الـ setup الحقيقي يصير في startCore
    fun setup(grpcPort: Int): String = ""

    // ─── startCore ────────────────────────────────────────────────────
    // الإصلاح: Mobile.setup() يُستدعى مرة واحدة فقط طول عمر العملية.
    // عند إعادة الاتصال: نكتفي بـ Mobile.start() مباشرة.
    fun startCore(platform: PlatformInterface, warpOverProxy: Boolean) {
        Log.d(TAG, "startCore — warpOverProxy=$warpOverProxy, mobileSetup=${mobileSetup.get()}")

        if (!mobileSetup.get()) {
            // أول مرة فقط — أو بعد closeAll() عند إغلاق التطبيق
            Mobile.setup(
                SetupOptions().also {
                    it.basePath        = baseDir
                    it.workingDir      = workingDir
                    it.tempDir         = tempDir
                    it.listen          = "127.0.0.1:9090"
                    it.secret          = ""
                    it.mode            = 4L
                    it.fixAndroidStack = true
                },
                platform
            )
            mobileSetup.set(true)
            Log.d(TAG, "Mobile.setup done (first time)")
        } else {
            Log.d(TAG, "Mobile.setup skipped — reusing existing engine")
        }

        Mobile.start(configPath, "")
        Log.d(TAG, "Mobile.start done ✅")
    }

    // ─── stopCore ─────────────────────────────────────────────────────
    // الإصلاح: فقط Mobile.stop() — لا نستدعي Mobile.close() هنا أبداً
    // Mobile.close() يدمر الـ engine ويمنع أي اتصال لاحق في نفس العملية
    fun stopCore() {
        Log.d(TAG, "stopCore — calling Mobile.stop() only")
        try {
            Mobile.stop()
            Log.d(TAG, "Mobile.stop() done")
        } catch (e: Exception) {
            Log.w(TAG, "Mobile.stop error: ${e.message}")
        }
        // ملاحظة: Mobile.close() محذوف عمداً — يُستدعى فقط من closeAll()
    }

    // ─── closeAll — يُستدعى عند إغلاق التطبيق نهائياً فقط ────────────
    fun closeAll() {
        Log.d(TAG, "closeAll — Mobile.stop + Mobile.close")
        try { Mobile.stop()    } catch (e: Exception) { Log.w(TAG, "stop: ${e.message}") }
        try { Mobile.close(4L) } catch (e: Exception) { Log.w(TAG, "close: ${e.message}") }
        mobileSetup.set(false)
    }
}

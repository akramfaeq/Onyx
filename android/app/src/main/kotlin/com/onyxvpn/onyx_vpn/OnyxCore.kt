package com.onyxvpn.onyx_vpn

import android.content.Context
import android.util.Log
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.mobile.Mobile
import com.hiddify.core.mobile.SetupOptions
import java.io.File
import java.io.InputStream
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import io.grpc.CallOptions
import io.grpc.ManagedChannelBuilder
import io.grpc.MethodDescriptor
import io.grpc.stub.ClientCalls
import java.util.concurrent.TimeUnit

object OnyxCore {
    private const val TAG = "OnyxCore"
    private var initialized = false

    lateinit var baseDir: String
    lateinit var workingDir: String
    lateinit var tempDir: String
    lateinit var configPath: String

    fun init(context: Context) {
        if (initialized) return
        baseDir = context.filesDir.path
        workingDir = (context.getExternalFilesDir(null) ?: context.filesDir).path
        tempDir = context.cacheDir.path
        configPath = "$workingDir/config.json"

        File(baseDir).mkdirs()
        File(workingDir).mkdirs()
        File(tempDir).mkdirs()

        runCatching { Libbox.redirectStderr(File(workingDir, "stderr.log").path) }
            .onFailure { Log.w(TAG, "redirectStderr failed: " + it.message) }
        initialized = true
    }

    // Core 4 uses Mobile.setup after the Android VpnService is available.
    fun setup(grpcPort: Int): String = ""

    fun writeConfig(json: String) {
        File(configPath).writeText(json)
    }

    fun checkConfig(json: String): String = try {
        Libbox.checkConfig(json)
        ""
    } catch (error: Exception) {
        error.message ?: "Invalid configuration"
    }

    fun startCore(platform: PlatformInterface, warpOverProxy: Boolean) {
        Mobile.setup(
            SetupOptions().also {
                it.basePath = baseDir
                it.workingDir = workingDir
                it.tempDir = tempDir
                it.listen = "127.0.0.1:9090"
                it.secret = ""
                it.mode = 4L
                it.fixAndroidStack = true
            },
            platform
        )
        updateHiddifySettings(warpOverProxy)
        Mobile.start(configPath, "")
    }

    private fun updateHiddifySettings(warpOverProxy: Boolean) {
        val channel = ManagedChannelBuilder.forAddress("127.0.0.1", 9090).usePlaintext().build()
        try {
            val requestMarshaller = object : MethodDescriptor.Marshaller<String> {
                override fun stream(value: String): InputStream {
                    val payload = value.toByteArray(Charsets.UTF_8)
                    val bytes = ByteArrayOutputStream()
                    bytes.write(0x0A)
                    writeVarint(bytes, payload.size)
                    bytes.write(payload)
                    return ByteArrayInputStream(bytes.toByteArray())
                }
                override fun parse(stream: InputStream): String = stream.readBytes().toString(Charsets.UTF_8)
            }
            val responseMarshaller = object : MethodDescriptor.Marshaller<ByteArray> {
                override fun stream(value: ByteArray): InputStream = ByteArrayInputStream(value)
                override fun parse(stream: InputStream): ByteArray = stream.readBytes()
            }
            val method = MethodDescriptor.newBuilder<String, ByteArray>()
                .setType(MethodDescriptor.MethodType.UNARY)
                .setFullMethodName(MethodDescriptor.generateFullMethodName("hcore.Core", "ChangeHiddifySettings"))
                .setRequestMarshaller(requestMarshaller)
                .setResponseMarshaller(responseMarshaller)
                .build()
            val settings = """{"enable-tun":true,"mtu":1280,"strict-route":false,"warp":{"enable":$warpOverProxy,"mode":"warp_over_proxy"}}"""
            ClientCalls.blockingUnaryCall(
                channel,
                method,
                CallOptions.DEFAULT.withDeadlineAfter(5, TimeUnit.SECONDS),
                settings
            )
        } finally {
            channel.shutdownNow()
        }
    }

    private fun writeVarint(output: ByteArrayOutputStream, input: Int) {
        var value = input
        while (value >= 0x80) {
            output.write((value and 0x7F) or 0x80)
            value = value ushr 7
        }
        output.write(value)
    }
    fun stopCore() {
        try {
            Mobile.stop()
        } finally {
            Mobile.close(4L)
        }
    }
}
package com.onyxvpn.onyx_vpn

import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * OnyxChannel — جسر التواصل بين Flutter والـ native
 */
object OnyxChannel {

    const val METHOD_CHANNEL = "com.onyxvpn/vpn"
    const val EVENT_CHANNEL  = "com.onyxvpn/status"

    private var eventSink: EventChannel.EventSink? = null
    private var methodChannel: MethodChannel? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun setMethodChannel(ch: MethodChannel) {
        methodChannel = ch
    }

    /** أرسل status لـ Flutter من أي thread */
    fun sendStatus(status: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(status)
            Log.d("OnyxChannel", "status → $status")
        }
    }
}

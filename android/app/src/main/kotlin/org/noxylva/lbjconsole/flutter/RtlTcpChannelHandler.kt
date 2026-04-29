package org.noxylva.lbjconsole.flutter 

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.nio.charset.Charset

class RtlTcpChannelHandler : EventChannel.StreamHandler {

    private external fun startClientAsync(host: String, port: String)
    private external fun pollMessages(): ByteArray
    private external fun nativeStopClient()
    private external fun getSignalStrength(): Double
    private external fun isConnected(): Boolean 

    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var lastConnectedState: Boolean = false 
    private val messageRegex = "\\[MSG\\]\\s*(\\d+)\\|(-?\\d+)\\|([^\\n]*)".toRegex()

    companion object {
        private const val METHOD_CHANNEL_NAME = "org.noxylva.lbjconsole/rtl_tcp_method"
        private const val EVENT_CHANNEL_NAME = "org.noxylva.lbjconsole/rtl_tcp_event"

        init {
            System.loadLibrary("railwaypagerdemod")
        }
        
        fun registerWith(flutterEngine: FlutterEngine) {
            val handler = RtlTcpChannelHandler()
            
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL_NAME).setMethodCallHandler {
                call, result ->
                when (call.method) {
                    "connect" -> {
                        val host = call.argument<String>("host")!!
                        val port = call.argument<String>("port")!!
                        android.util.Log.d("RTL-TCP", "conn_req: $host:$port")
                        try {
                            handler.startClientAsync(host, port)
                            android.util.Log.d("RTL-TCP", "conn_sent")
                            result.success("Connect command sent.")
                        } catch (e: Exception) {
                            android.util.Log.e("RTL-TCP", "conn_fail", e)
                            result.error("CONNECT_ERROR", "连接失败: ${e.message}", null)
                        }
                    }
                    "disconnect" -> {
                        android.util.Log.d("RTL-TCP", "disc_req")
                        handler.nativeStopClient()
                        result.success("Disconnect command completed.")
                    }
                    else -> result.notImplemented()
                }
            }
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME).setStreamHandler(handler)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        android.util.Log.d("RTL-TCP", "evt_listen")
        this.eventSink = events
        lastConnectedState = true
        startPolling() 
    }

    override fun onCancel(arguments: Any?) {
        android.util.Log.d("RTL-TCP", "evt_cancel")
        handler.removeCallbacksAndMessages(null) 
        this.eventSink = null
    }

    private fun startPolling() {
        handler.post(object : Runnable {
            override fun run() {
                if (eventSink == null) {
                    return;
                }
                val connected = try {
                    isConnected()
                } catch (e: Exception) {
                    android.util.Log.e("RTL-TCP", "isConnected() failed", e)
                    false
                }

                val strength = try {
                    getSignalStrength()
                } catch (e: Exception) {
                    android.util.Log.e("RTL-TCP", "getSignalStrength() failed", e)
                    0.0
                }

                val logsBytes = try {
                    pollMessages()
                } catch (e: Exception) {
                    android.util.Log.e("RTL-TCP", "pollMessages() failed", e)
                    ByteArray(0)
                }

                val logs = if (logsBytes.isNotEmpty()) String(logsBytes, Charsets.ISO_8859_1) else ""

                if (connected != lastConnectedState) {
                    val statusMap = mutableMapOf<String, Any?>()
                    statusMap["connected"] = connected
                    statusMap["magsqRaw"] = strength
                    try {
                        eventSink?.success(statusMap)
                    } catch (e: Exception) {
                        android.util.Log.e("RTL-TCP", "eventSink status send failed", e)
                    }
                    lastConnectedState = connected
                }

                if (logs.isNotEmpty()) {
                    messageRegex.findAll(logs).forEach { match ->
                        try {
                            val addr = match.groupValues[1]
                            val func = match.groupValues[2]
                            val content = match.groupValues[3]

                            val dataMap = mutableMapOf<String, Any?>()
                            dataMap["address"] = addr
                            dataMap["func"] = func
                            dataMap["numeric"] = content
                            dataMap["magsqRaw"] = strength

                            try {
                                eventSink?.success(dataMap)
                            } catch (e: Exception) {
                                android.util.Log.e("RTL-TCP", "eventSink data send failed", e)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("RTL-TCP", "decode_fail", e)
                        }
                    }
                }

                handler.postDelayed(this, 200)
            }
        })
    }
}

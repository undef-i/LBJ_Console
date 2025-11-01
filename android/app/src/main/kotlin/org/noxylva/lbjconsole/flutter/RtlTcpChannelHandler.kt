package org.noxylva.lbjconsole.flutter 

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.nio.charset.Charset

class RtlTcpChannelHandler : EventChannel.StreamHandler {

    private external fun startClientAsync(host: String, port: String)
    private external fun pollMessages(): String
    private external fun nativeStopClient()
    private external fun getSignalStrength(): Double
    private external fun isConnected(): Boolean 

    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var lastConnectedState: Boolean = false 

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
                    android.util.Log.w("RTL-TCP", "evt_null");
                    return;
                }
            
                val connected = isConnected()
                val strength = getSignalStrength() 
                val logs = pollMessages()
                val regex = "\\[MSG\\]\\s*(\\d+)\\|(-?\\d+)\\|(.*)".toRegex() 

                if (connected != lastConnectedState || connected) {
                    val statusMap = mutableMapOf<String, Any?>()
                    statusMap["connected"] = connected
                    statusMap["magsqRaw"] = strength
                    eventSink?.success(statusMap)
                    lastConnectedState = connected
                }

                if (logs.isNotEmpty()) {
                    regex.findAll(logs).forEach { match ->
                        try {
                            val dataMap = mutableMapOf<String, Any?>()
                            dataMap["address"] = match.groupValues[1]
                            dataMap["func"] = match.groupValues[2]
                            
                            val gbkBytes = match.groupValues[3].toByteArray(Charsets.ISO_8859_1)
                            val utf8String = String(gbkBytes, Charset.forName("GBK"))
                            dataMap["numeric"] = utf8String
                            
                            dataMap["magsqRaw"] = strength 

                            eventSink?.success(dataMap)
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
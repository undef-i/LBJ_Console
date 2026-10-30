package org.noxylva.lbjconsole.flutter

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class UsbSdrHandler(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    private var connection: UsbDeviceConnection? = null
    private var sessionDeviceName: String? = null

    @Volatile
    private var armed = false

    @Volatile
    private var permissionPending = false

    @Volatile
    private var resetUsedInStreak = false

    @Volatile
    private var currentOp: String = ""

    @Volatile
    private var currentOpSince: Long = 0L

    private fun beginOp(name: String) {
        currentOp = name
        currentOpSince = SystemClock.elapsedRealtime()
    }

    private fun endOp() {
        currentOp = ""
        currentOpSince = 0L
    }

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            try {
                if (intent.action != ACTION_USB_PERMISSION) return
                permissionPending = false
                val device: UsbDevice? = intent.parcelableDevice()
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                if (device != null && granted) {
                    startSession(device)
                } else {
                    emit(mapOf("state" to "denied"))
                }
            } catch (e: Exception) {
                emit(errorEvent(-3900, e))
            }
        }
    }

    private val attachReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            try {
                if (intent.action != UsbManager.ACTION_USB_DEVICE_ATTACHED) return
                if (!armed) return
                val device: UsbDevice? = intent.parcelableDevice()
                if (device != null && (isRtlDevice(device) || isPlutoDevice(device))) {
                    startSession(device)
                }
            } catch (e: Exception) {
                emit(errorEvent(-3900, e))
            }
        }
    }

    private val detachReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            try {
                if (intent.action != UsbManager.ACTION_USB_DEVICE_DETACHED) return
                permissionPending = false
                val device: UsbDevice? = intent.parcelableDevice()
                if (device != null && device.deviceName == sessionDeviceName) {
                    stopSession()
                    emit(mapOf("state" to "detached"))
                }
            } catch (e: Exception) {
                emit(errorEvent(-3900, e))
            }
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "org.noxylva.lbjconsole/usb_sdr"
        private const val EVENT_CHANNEL = "org.noxylva.lbjconsole/usb_sdr_event"
        private const val ACTION_USB_PERMISSION = "org.noxylva.lbjconsole.USB_PERMISSION"
        private const val STOP_GRACE_MS = 2000L

        private val KNOWN_DEVICES = setOf(
            3034 to 10290, 3034 to 10296, 1043 to 26240, 1043 to 28431, 1112 to 28799,
            3277 to 169, 3277 to 179, 3277 to 180, 3277 to 181, 3277 to 183, 3277 to 184,
            3277 to 185, 3277 to 192, 3277 to 198, 3277 to 211, 3277 to 215, 3277 to 224,
            5460 to 20512, 5620 to 305, 5620 to 307, 6235 to 1568, 6235 to 1616, 6235 to 1664,
            7040 to 54163, 7040 to 54164, 7040 to 54165, 7040 to 54167, 7040 to 54168,
            7040 to 54173, 7040 to 54180, 7040 to 54184, 7040 to 54191, 7040 to 54192,
            7449 to 4353, 7449 to 4354, 7449 to 4355, 7449 to 4356, 8013 to 43011,
            8013 to 47107, 8013 to 51203, 8013 to 53894, 8013 to 55299
        )

        fun isRtlDevice(device: UsbDevice): Boolean =
            KNOWN_DEVICES.contains(device.vendorId to device.productId)

        fun isPlutoDevice(device: UsbDevice): Boolean =
            device.vendorId == 1110 && device.productId == 46707

        @Volatile
        var pendingAttachLaunch = false
            private set

        fun consumePendingAttachLaunch(): Boolean {
            val launched = pendingAttachLaunch
            pendingAttachLaunch = false
            return launched
        }

        private var instance: UsbSdrHandler? = null

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            instance?.dispose()
            val handler = UsbSdrHandler(context)
            instance = handler
            val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            methodChannel.setMethodCallHandler(handler)
            val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            eventChannel.setStreamHandler(handler)
            handler.registerReceivers()
        }

        fun handleIntent(intent: Intent?) {
            try {
                val handler = instance ?: return
                if (intent?.action != UsbManager.ACTION_USB_DEVICE_ATTACHED) return
                val device: UsbDevice? = intent.parcelableDevice()
                if (device != null && (isRtlDevice(device) || isPlutoDevice(device))) {
                    pendingAttachLaunch = true
                    handler.startSession(device)
                }
            } catch (e: Exception) {
                val h = instance ?: return
                h.emit(h.errorEvent(-3900, e))
            }
        }
    }

    private fun registerReceivers() {
        ContextCompat.registerReceiver(
            context, permissionReceiver,
            IntentFilter(ACTION_USB_PERMISSION),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        ContextCompat.registerReceiver(
            context, attachReceiver,
            IntentFilter(UsbManager.ACTION_USB_DEVICE_ATTACHED),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        ContextCompat.registerReceiver(
            context, detachReceiver,
            IntentFilter(UsbManager.ACTION_USB_DEVICE_DETACHED),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    private fun isSupported(device: UsbDevice): Boolean =
        isRtlDevice(device) || isPlutoDevice(device)

    private fun findAttachedDevice(): UsbDevice? =
        usbManager.deviceList.values.firstOrNull { isSupported(it) }

    private fun attemptStart(onResult: ((String) -> Unit)? = null) {
        val device = findAttachedDevice()
        when {
            device == null -> {
                val seen = usbManager.deviceList.values.joinToString("，") {
                    "${it.productName ?: "USB"} ${it.vendorId}:${it.productId}"
                }
                emit(mapOf("state" to "no_device", "seen" to seen))
                onResult?.invoke("no_device")
            }
            usbManager.hasPermission(device) -> {
                startSession(device)
                onResult?.invoke("starting")
            }
            permissionPending -> onResult?.invoke("permission_requested")
            else -> {
                permissionPending = true
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                val intent = Intent(ACTION_USB_PERMISSION)
                    .setPackage(context.packageName)
                val pi = PendingIntent.getBroadcast(context, 0, intent, flags)
                usbManager.requestPermission(device, pi)
                emit(mapOf("state" to "permission_requested"))
                onResult?.invoke("permission_requested")
            }
        }
    }

    private fun describeDevice(device: UsbDevice): String {
        val parts = ArrayList<String>()
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            val name = if (Build.VERSION.SDK_INT >= 28) {
                intf.name ?: "无名"
            } else {
                "无名"
            }
            parts.add("接口$i 类${intf.interfaceClass} 名：$name")
        }
        return parts.joinToString("；")
    }

    fun startSession(device: UsbDevice) {
        executor.execute {
            beginOp(if (isPlutoDevice(device)) "start-pluto" else "start-rtl")
            try {
                stopSessionLocked()
                val pluto = isPlutoDevice(device)
                val iioIfnum = if (pluto) {
                    (0 until device.interfaceCount)
                        .map { device.getInterface(it) }
                        .firstOrNull { it.name == "IIO" }?.id ?: -1
                } else {
                    -1
                }
                if (pluto && iioIfnum < 0) {
                    emit(mapOf("state" to "error", "code" to -3012,
                        "message" to describeDevice(device)))
                    return@execute
                }
                val conn = usbManager.openDevice(device)
                if (conn == null) {
                    emit(mapOf("state" to "error", "code" to -3000,
                        "message" to describeDevice(device)))
                    return@execute
                }
                val r = if (pluto) {
                    LbjUsbNative.nativeStartPluto(conn.fileDescriptor, iioIfnum)
                } else {
                    LbjUsbNative.nativeStart(conn.fileDescriptor)
                }
                if (r == 0 || r == -2000) {
                    resetUsedInStreak = false
                    connection = conn
                    sessionDeviceName = device.deviceName
                    emit(mapOf("state" to "ready"))
                } else if (!pluto && r in -2499..-2400 && !resetUsedInStreak) {
                    resetUsedInStreak = true
                    conn.close()
                    val resetConn = usbManager.openDevice(device)
                    if (resetConn != null) {
                        LbjUsbNative.nativeReset(resetConn.fileDescriptor)
                        resetConn.close()
                    }
                } else {
                    conn.close()
                    emit(mapOf("state" to "error", "code" to r,
                        "message" to describeDevice(device)))
                }
            } catch (e: Exception) {
                emit(errorEvent(-3901, e))
            } finally {
                endOp()
            }
        }
    }

    fun stopSession() {
        executor.execute {
            beginOp("stop")
            try {
                stopSessionLocked()
            } catch (e: Exception) {
                emit(errorEvent(-3902, e))
            } finally {
                endOp()
            }
        }
    }

    private fun stopSessionLocked() {
        val conn = connection
        connection = null
        sessionDeviceName = null
        var closed = false
        if (LbjUsbNative.nativeIsRunning()) {
            val stopper = Thread { LbjUsbNative.nativeStop() }
            stopper.start()
            stopper.join(STOP_GRACE_MS)
            if (stopper.isAlive) {
                conn?.close()
                closed = true
                stopper.join()
            }
        }
        if (!closed) {
            conn?.close()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                armed = true
                permissionPending = false
                attemptStart { result.success(it) }
            }
            "stop" -> {
                armed = false
                permissionPending = false
                stopSession()
                result.success(null)
            }
            "isRunning" -> result.success(LbjUsbNative.nativeIsRunning())
            "exitError" -> result.success(LbjUsbNative.nativeExitError())
            "opState" -> {
                val op = currentOp
                if (op.isEmpty()) {
                    result.success("")
                } else {
                    val secs =
                        (SystemClock.elapsedRealtime() - currentOpSince) / 1000
                    result.success("$op|${LbjUsbNative.nativeStage()}|$secs")
                }
            }
            "consumeAttachLaunch" -> {
                result.success(consumePendingAttachLaunch())
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        events?.success(mapOf("state" to if (LbjUsbNative.nativeIsRunning()) "ready" else "idle"))
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emit(event: Map<String, Any?>) {
        handler.post { eventSink?.success(event) }
    }

    private fun errorEvent(code: Int, e: Exception): Map<String, Any?> =
        mapOf(
            "state" to "error",
            "code" to code,
            "message" to "${e.javaClass.simpleName}: ${e.message ?: ""}"
        )

    private fun dispose() {
        try { context.unregisterReceiver(permissionReceiver) } catch (e: Exception) {}
        try { context.unregisterReceiver(attachReceiver) } catch (e: Exception) {}
        try { context.unregisterReceiver(detachReceiver) } catch (e: Exception) {}
        eventSink = null
        executor.shutdownNow()
    }
}

@Suppress("DEPRECATION")
private fun Intent.parcelableDevice(): UsbDevice? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
    } else {
        getParcelableExtra(UsbManager.EXTRA_DEVICE) as? UsbDevice
    }

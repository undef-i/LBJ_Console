package receiver.lbj

import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.nio.charset.StandardCharsets
import org.json.JSONObject
import java.util.*

class BLEClient(private val context: Context) : BluetoothGattCallback(),
    BluetoothAdapter.LeScanCallback {
    companion object {
        const val TAG = "LBJ_BT"
        const val SCAN_PERIOD = 10000L

        val SERVICE_UUID = UUID.fromString("0000ffe0-0000-1000-8000-00805f9b34fb")
        val CHAR_UUID = UUID.fromString("0000ffe1-0000-1000-8000-00805f9b34fb")

        const val CMD_GET_STATUS = "STATUS"

        const val RESP_STATUS = "STATUS:"
        const val RESP_ERROR = "ERROR:"
    }

    private var bluetoothGatt: BluetoothGatt? = null
    private var deviceAddress: String? = null
    private var isConnected = false
    private var isScanning = false
    private var statusCallback: ((String) -> Unit)? = null
    private var scanCallback: ((BluetoothDevice) -> Unit)? = null
    private var connectionStateCallback: ((Boolean) -> Unit)? = null
    private var trainInfoCallback: ((JSONObject) -> Unit)? = null
    private var handler = Handler(Looper.getMainLooper())
    private var targetDeviceName: String? = null


    fun setTrainInfoCallback(callback: (JSONObject) -> Unit) {
        trainInfoCallback = callback
    }


    @SuppressLint("MissingPermission")
    fun scanDevices(targetDeviceName: String? = null, callback: (BluetoothDevice) -> Unit) {
        try {
            scanCallback = callback
            this.targetDeviceName = targetDeviceName
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter() ?: run {
                Log.e(TAG, "Bluetooth adapter unavailable")
                return
            }

            if (!bluetoothAdapter.isEnabled) {
                Log.e(TAG, "Bluetooth adapter disabled")
                return
            }

            handler.postDelayed({
                stopScan()
            }, SCAN_PERIOD)

            isScanning = true
            Log.d(TAG, "Starting BLE scan target=${targetDeviceName ?: "Any"}")
            bluetoothAdapter.startLeScan(this)
        } catch (e: SecurityException) {
            Log.e(TAG, "Scan security error: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "BLE scan failed: ${e.message}")
        }
    }


    @SuppressLint("MissingPermission")
    fun stopScan() {
        if (isScanning) {
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            bluetoothAdapter.stopLeScan(this)
            isScanning = false
        }
    }


    override fun onLeScan(device: BluetoothDevice, rssi: Int, scanRecord: ByteArray) {

        val deviceName = device.name
        if (targetDeviceName != null) {

            if (deviceName == null || !deviceName.equals(targetDeviceName, ignoreCase = true)) {
                return
            }
        }
        scanCallback?.invoke(device)
    }


    @SuppressLint("MissingPermission")
    fun connect(address: String, onConnectionStateChange: ((Boolean) -> Unit)? = null): Boolean {
        if (address.isBlank()) {
            Log.e(TAG, "Connection failed empty address")
            handler.post { onConnectionStateChange?.invoke(false) }
            return false
        }

        try {
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter() ?: run {
                Log.e(TAG, "Bluetooth adapter unavailable")
                handler.post { onConnectionStateChange?.invoke(false) }
                return false
            }


            bluetoothGatt?.close()
            bluetoothGatt = null

            val device = bluetoothAdapter.getRemoteDevice(address)

            deviceAddress = address
            connectionStateCallback = onConnectionStateChange


            bluetoothGatt = device.connectGatt(context, false, this, BluetoothDevice.TRANSPORT_LE)

            Log.d(TAG, "Connecting to address=$address")


            handler.postDelayed({
                if (!isConnected && deviceAddress == address) {
                    Log.e(TAG, "Connection timeout reconnecting")

                    bluetoothGatt?.close()
                    bluetoothGatt =
                        device.connectGatt(context, false, this, BluetoothDevice.TRANSPORT_LE)
                }
            }, 10000)

            return true
        } catch (e: Exception) {
            Log.e(TAG, "Connection failed: ${e.message}")
            handler.post { onConnectionStateChange?.invoke(false) }
            return false
        }
    }


    fun isConnected(): Boolean {
        return isConnected
    }


    @SuppressLint("MissingPermission")
    fun disconnect() {
        bluetoothGatt?.disconnect()
    }


    @SuppressLint("MissingPermission")
    fun getStatus(callback: (String) -> Unit) {
        statusCallback = callback
        bluetoothGatt?.let { gatt ->
            val service = gatt.getService(SERVICE_UUID)
            if (service != null) {
                val characteristic = service.getCharacteristic(CHAR_UUID)
                if (characteristic != null) {
                    characteristic.value = CMD_GET_STATUS.toByteArray()
                    gatt.writeCharacteristic(characteristic)
                } else {
                    Log.e(TAG, "Characteristic not found")
                    statusCallback?.invoke("ERROR: Characteristic not found")
                }
            } else {
                Log.e(TAG, "Service not found")
                statusCallback?.invoke("ERROR: Service not found")
            }
        }
    }


    override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
        super.onServicesDiscovered(gatt, status)

        if (status == BluetoothGatt.GATT_SUCCESS) {
            Log.i(TAG, "Discovered GATT services")
            requestMtu(gatt)
        } else {
            Log.w(TAG, "Service discovery failed status=$status")

            handler.post {
                connectionStateCallback?.invoke(false)
            }
        }
    }


    @SuppressLint("MissingPermission")
    private fun requestMtu(gatt: BluetoothGatt) {
        try {
            Log.d(TAG, "Requesting MTU size=512")
            gatt.requestMtu(512)
        } catch (e: Exception) {
            Log.e(TAG, "MTU request failed: ${e.message}")

            enableNotification()
        }
    }


    override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
        super.onMtuChanged(gatt, mtu, status)

        if (status == BluetoothGatt.GATT_SUCCESS) {
            Log.d(TAG, "MTU set to $mtu")
        } else {
            Log.w(TAG, "MTU change failed status=$status")
        }


        enableNotification()
    }


    override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
        super.onConnectionStateChange(gatt, status, newState)

        if (status != BluetoothGatt.GATT_SUCCESS) {
            Log.e(TAG, "Connection error status=$status")
            isConnected = false


            if (status == 133 || status == 8) {
                Log.e(TAG, "GATT error closing connection")
                try {
                    gatt.close()
                    bluetoothGatt = null


                    deviceAddress?.let { address ->
                        handler.postDelayed({
                            Log.d(TAG, "Reconnecting to device")
                            val device =
                                BluetoothAdapter.getDefaultAdapter().getRemoteDevice(address)
                            bluetoothGatt = device.connectGatt(
                                context,
                                false,
                                this,
                                BluetoothDevice.TRANSPORT_LE
                            )
                        }, 2000)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Reconnect error: ${e.message}")
                }
            }

            handler.post { connectionStateCallback?.invoke(false) }
            return
        }

        when (newState) {
            BluetoothProfile.STATE_CONNECTED -> {
                isConnected = true
                Log.i(TAG, "Connected to GATT server")

                handler.post { connectionStateCallback?.invoke(true) }


                handler.postDelayed({
                    try {
                        gatt.discoverServices()
                    } catch (e: Exception) {
                        Log.e(TAG, "Service discovery failed: ${e.message}")
                    }
                }, 500)
            }

            BluetoothProfile.STATE_DISCONNECTED -> {
                isConnected = false
                Log.i(TAG, "Disconnected from GATT server")

                handler.post { connectionStateCallback?.invoke(false) }


                if (!deviceAddress.isNullOrBlank()) {
                    handler.postDelayed({
                        Log.d(TAG, "Reconnecting after disconnect")
                        connect(deviceAddress!!, connectionStateCallback)
                    }, 3000)
                }
            }
        }
    }


    private val dataBuffer = StringBuilder()
    private val maxBufferSize = 1024 * 1024
    private var lastDataTime = 0L


    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic
    ) {
        super.onCharacteristicChanged(gatt, characteristic)

        val newData = characteristic.value?.let {
            String(it, StandardCharsets.UTF_8)
        } ?: return

        Log.d(TAG, "Received data len=${newData.length} preview=${newData.take(50)}")


        dataBuffer.append(newData)


        checkAndProcessCompleteJson()
    }


    private fun checkAndProcessCompleteJson() {
        val bufferContent = dataBuffer.toString()
        val currentTime = System.currentTimeMillis()


        if (lastDataTime > 0 && currentTime - lastDataTime > 5000) {
            Log.w(TAG, "Data timeout ${(currentTime - lastDataTime) / 1000}s")

        }

        Log.d(TAG, "Buffer size=${dataBuffer.length} bytes")


        tryExtractJson(bufferContent)


        lastDataTime = currentTime
    }


    private fun tryExtractJson(bufferContent: String) {

        val openBracesCount = bufferContent.count { it == '{' }
        val closeBracesCount = bufferContent.count { it == '}' }


        if (openBracesCount > 0 && openBracesCount == closeBracesCount) {
            Log.d(TAG, "Found JSON braces=${openBracesCount}")


            val firstOpenBrace = bufferContent.indexOf('{')
            val lastCloseBrace = bufferContent.lastIndexOf('}')

            if (firstOpenBrace >= 0 && lastCloseBrace > firstOpenBrace) {
                val possibleJson = bufferContent.substring(firstOpenBrace, lastCloseBrace + 1)

                if (processJsonString(possibleJson)) {

                    dataBuffer.delete(0, lastCloseBrace + 1)
                    return
                }
            }
        }


        val firstOpenBrace = bufferContent.indexOf('{')
        if (firstOpenBrace >= 0) {

            var openCount = 0
            var closeCount = 0
            var currentEnd = -1

            for (i in firstOpenBrace until bufferContent.length) {
                if (bufferContent[i] == '{') {
                    openCount++
                } else if (bufferContent[i] == '}') {
                    closeCount++
                    if (openCount == closeCount) {
                        currentEnd = i
                        break
                    }
                }
            }

            if (currentEnd > firstOpenBrace) {
                val possibleJson = bufferContent.substring(firstOpenBrace, currentEnd + 1)
                Log.d(TAG, "Parsing JSON=${possibleJson.take(30)}...")

                if (processJsonString(possibleJson)) {

                    dataBuffer.delete(0, currentEnd + 1)
                    return
                }
            }
        }


        if (dataBuffer.length > 1000) {
            Log.w(TAG, "Large buffer ${dataBuffer.length} bytes")


            val lastJsonStart = dataBuffer.lastIndexOf("{")
            if (lastJsonStart > 0) {
                dataBuffer.delete(0, lastJsonStart)
                Log.d(TAG, "Kept JSON buffer=${dataBuffer.length} bytes")
            } else {

                dataBuffer.delete(0, dataBuffer.length / 2)
                Log.d(TAG, "Cleared buffer size=${dataBuffer.length}")
            }
        }
    }


    private fun processJsonString(jsonStr: String): Boolean {
        try {
            val jsonObject = JSONObject(jsonStr)
            Log.d(TAG, "Parsed JSON len=${jsonStr.length} preview=${jsonStr.take(50)}")


            handler.post {
                statusCallback?.invoke(jsonStr)


                if (jsonObject.has("train")) {
                    Log.d(TAG, "Found train data")
                    trainInfoCallback?.invoke(jsonObject)
                }
            }

            return true
        } catch (e: Exception) {
            Log.d(TAG, "JSON parse failed: ${e.message}")
            return false
        }
    }


    @SuppressLint("MissingPermission")
    private fun enableNotification() {
        bluetoothGatt?.let { gatt ->
            try {
                val service = gatt.getService(SERVICE_UUID)
                if (service != null) {
                    val characteristic = service.getCharacteristic(CHAR_UUID)
                    if (characteristic != null) {
                        val result = gatt.setCharacteristicNotification(characteristic, true)
                        Log.d(TAG, "Notification set result=$result")

                        try {
                            val descriptor = characteristic.getDescriptor(
                                UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
                            )
                            if (descriptor != null) {
                                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                                val writeResult = gatt.writeDescriptor(descriptor)
                                Log.d(TAG, "Descriptor write result=$writeResult")
                            } else {
                                Log.e(TAG, "Descriptor not found")

                                requestDataAfterDelay()
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Descriptor write error: ${e.message}")
                            requestDataAfterDelay()
                        }
                    } else {
                        Log.e(TAG, "Characteristic not found")
                        requestDataAfterDelay()
                    }
                } else {
                    Log.e(TAG, "Service not found")
                    requestDataAfterDelay()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Notification setup error: ${e.message}")
                requestDataAfterDelay()
            }
        }
    }


    private fun requestDataAfterDelay() {
        handler.postDelayed({
            statusCallback?.let { callback ->
                getStatus(callback)
            }
        }, 1000)
    }
}
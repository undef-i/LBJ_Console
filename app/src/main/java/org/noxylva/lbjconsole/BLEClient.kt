package org.noxylva.lbjconsole

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import java.nio.charset.StandardCharsets
import org.json.JSONObject
import java.util.*

class BLEClient(private val context: Context) : BluetoothGattCallback() {
    companion object {
        const val TAG = "LBJ_BT"        
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
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    
    private var continuousScanning = false
    private var autoReconnect = true
    private var lastKnownDeviceAddress: String? = null
    private var connectionAttempts = 0
    private var isReconnecting = false
    private var highFrequencyReconnect = true
    private var reconnectHandler = Handler(Looper.getMainLooper())
    private var reconnectRunnable: Runnable? = null
    private var connectionLostCallback: (() -> Unit)? = null
    private var connectionSuccessCallback: ((String) -> Unit)? = null
    private var specifiedDeviceAddress: String? = null
    private var targetDeviceAddress: String? = null
    private var isDialogOpen = false
    private var isManualDisconnect = false
    private var isAutoConnectBlocked = false
    
    private val leScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val deviceName = device.name
            
            val shouldShowDevice = when {
                targetDeviceName != null -> {
                    deviceName != null && deviceName.equals(targetDeviceName, ignoreCase = true)
                }
                else -> {
                    true
                }
            }
            
            if (shouldShowDevice) {
                Log.d(TAG, "Showing filtered device: $deviceName")
                scanCallback?.invoke(device)
            }
            
            if (!isConnected && !isReconnecting && !isDialogOpen && !isAutoConnectBlocked) {
                val deviceAddress = device.address
                val isSpecifiedDevice = specifiedDeviceAddress == deviceAddress
                val isTargetDevice = targetDeviceName != null && deviceName != null && deviceName.equals(targetDeviceName, ignoreCase = true)
                val isKnownDevice = lastKnownDeviceAddress == deviceAddress
                val isSpecificTargetAddress = targetDeviceAddress == deviceAddress
                
                if (isSpecificTargetAddress || isSpecifiedDevice || (specifiedDeviceAddress == null && isTargetDevice) || (specifiedDeviceAddress == null && isKnownDevice)) {
                    val priority = when {
                        isSpecificTargetAddress -> "specific target address"
                        isSpecifiedDevice -> "specified device"
                        isTargetDevice -> "target device name"
                        else -> "known device"
                    }
                    Log.i(TAG, "Found device ($priority): $deviceName, auto-connecting")
                    lastKnownDeviceAddress = deviceAddress
                    connectImmediately(deviceAddress)
                }
            }
        }
        
        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE scan failed code=$errorCode")
            if (continuousScanning) {
                handler.post {
                    restartScan()
                }
            }
        }
    }


    fun setTrainInfoCallback(callback: (JSONObject) -> Unit) {
        trainInfoCallback = callback
    }


    private fun hasBluetoothPermissions(): Boolean {
        val bluetoothPermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_ADMIN) == PackageManager.PERMISSION_GRANTED
        }
        
        val locationPermissions = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        
        return bluetoothPermissions && locationPermissions
    }

    @SuppressLint("MissingPermission")
    fun scanDevices(targetDeviceName: String? = null, callback: (BluetoothDevice) -> Unit) {
        if (!hasBluetoothPermissions()) {
            Log.e(TAG, "Bluetooth permissions not granted")
            return
        }

        try {
            scanCallback = callback
            this.targetDeviceName = targetDeviceName
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val bluetoothAdapter = bluetoothManager.adapter ?: run {
                Log.e(TAG, "Bluetooth adapter unavailable")
                return
            }

            if (bluetoothAdapter.isEnabled != true) {
                Log.e(TAG, "Bluetooth adapter disabled")
                return
            }

            bluetoothLeScanner = bluetoothAdapter.bluetoothLeScanner
            if (bluetoothLeScanner == null) {
                Log.e(TAG, "BluetoothLeScanner unavailable")
                return
            }

            isScanning = true
            continuousScanning = true
            Log.d(TAG, "Starting continuous BLE scan target=${targetDeviceName ?: "Any"}")
            bluetoothLeScanner?.startScan(leScanCallback)
        } catch (e: SecurityException) {
            Log.e(TAG, "Scan security error: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "BLE scan failed: ${e.message}")
        }
    }


    @SuppressLint("MissingPermission")
    fun stopScan() {
        if (isScanning) {
            bluetoothLeScanner?.stopScan(leScanCallback)
            isScanning = false
            continuousScanning = false
            Log.d(TAG, "Stopped BLE scan")
        }
    }
    
    @SuppressLint("MissingPermission")
    private fun restartScan() {
        if (!continuousScanning) return
        
        try {
            bluetoothLeScanner?.stopScan(leScanCallback)
            bluetoothLeScanner?.startScan(leScanCallback)
            isScanning = true
            Log.d(TAG, "Restarted BLE scan")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restart scan: ${e.message}")
        }
    }
    
    private fun connectImmediately(address: String) {
        if (isReconnecting) return
        isReconnecting = true
        
        handler.post {
            connect(address) { connected ->
                isReconnecting = false
                if (connected) {
                    connectionAttempts = 0
                    Log.i(TAG, "Successfully connected to $address")
                } else {
                    connectionAttempts++
                    Log.w(TAG, "Connection attempt $connectionAttempts failed for $address")
                }
            }
        }
    }





    @SuppressLint("MissingPermission")
    fun connect(address: String, onConnectionStateChange: ((Boolean) -> Unit)? = null): Boolean {
        Log.d(TAG, "Attempting to connect to device: $address")
        
        if (!hasBluetoothPermissions()) {
            Log.e(TAG, "Bluetooth permissions not granted")
            handler.post { onConnectionStateChange?.invoke(false) }
            return false
        }

        if (address.isBlank()) {
            Log.e(TAG, "Connection failed empty address")
            handler.post { onConnectionStateChange?.invoke(false) }
            return false
        }

        try {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val bluetoothAdapter = bluetoothManager.adapter ?: run {
                Log.e(TAG, "Bluetooth adapter unavailable")
                handler.post { onConnectionStateChange?.invoke(false) }
                return false
            }
            
            if (bluetoothAdapter.isEnabled != true) {
                Log.e(TAG, "Bluetooth adapter is disabled")
                handler.post { onConnectionStateChange?.invoke(false) }
                return false
            }
            
            if (isConnected) {
                Log.w(TAG, "Already connected to device")
                handler.post { onConnectionStateChange?.invoke(true) }
                return true
            }


            bluetoothGatt?.close()
            bluetoothGatt = null

            val device = bluetoothAdapter.getRemoteDevice(address)

            deviceAddress = address
            connectionStateCallback = onConnectionStateChange


            bluetoothGatt = device.connectGatt(context, false, this, BluetoothDevice.TRANSPORT_LE)

            Log.d(TAG, "Connecting to address=$address")
            

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
    fun checkActualConnectionState(): Boolean {
        bluetoothGatt?.let { gatt ->
            try {
                val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                val connectedDevices = bluetoothManager.getConnectedDevices(BluetoothProfile.GATT)
                val isActuallyConnected = connectedDevices.any { it.address == deviceAddress }
                
                if (isActuallyConnected && !isConnected) {
                    Log.d(TAG, "Found existing GATT connection, updating internal state")
                    isConnected = true
                    return true
                } else if (!isActuallyConnected && isConnected) {
                    Log.d(TAG, "GATT connection lost, updating internal state")
                    isConnected = false
                    return false
                }
                
                return isActuallyConnected
            } catch (e: Exception) {
                Log.e(TAG, "Error checking actual connection state: ${e.message}")
                return isConnected
            }
        }
        return isConnected
    }


    @SuppressLint("MissingPermission")
    fun disconnect() {
        Log.d(TAG, "Manual disconnect initiated")
        isConnected = false
        isManualDisconnect = true
        isAutoConnectBlocked = true
        stopHighFrequencyReconnect()
        stopScan()
        
        bluetoothGatt?.let { gatt ->
            try {
                gatt.disconnect()
                Thread.sleep(100)
                gatt.close()
            } catch (e: Exception) {
                Log.e(TAG, "Disconnect error: ${e.message}")
            }
        }
        bluetoothGatt = null
        
        dataBuffer.clear()
        connectionStateCallback = null
        
        Log.d(TAG, "Manual disconnect - auto connect blocked, deviceAddress preserved: $deviceAddress")
    }
    
    @SuppressLint("MissingPermission")
    fun connectManually(address: String, onConnectionStateChange: ((Boolean) -> Unit)? = null): Boolean {
        Log.d(TAG, "Manual connection to device: $address")
        
        stopScan()
        stopHighFrequencyReconnect()
        
        isManualDisconnect = false
        isAutoConnectBlocked = false
        autoReconnect = true
        highFrequencyReconnect = true
        return connect(address, onConnectionStateChange)
    }
    
    @SuppressLint("MissingPermission")
    fun closeManually() {
        Log.d(TAG, "Manual close - will restore auto reconnect")
        
        isConnected = false
        isManualDisconnect = false
        isAutoConnectBlocked = false
        bluetoothGatt?.let { gatt ->
            try {
                gatt.disconnect()
                gatt.close()
            } catch (e: Exception) {
                Log.e(TAG, "Close error: ${e.message}")
            }
        }
        bluetoothGatt = null
        deviceAddress = null
        
        autoReconnect = true
        highFrequencyReconnect = true
        
        Log.d(TAG, "Auto reconnect mechanism restored and GATT cleaned up")
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
            isReconnecting = false

            if (status == 133 || status == 8) {
                Log.e(TAG, "GATT error, attempting immediate reconnection")
                try {
                    gatt.close()
                    bluetoothGatt = null
                    bluetoothLeScanner = null

                    deviceAddress?.let { address ->
                        if (autoReconnect) {
                            Log.d(TAG, "Immediate reconnection to device")
                            handler.post {
                                val device = BluetoothAdapter.getDefaultAdapter().getRemoteDevice(address)
                                bluetoothGatt = device.connectGatt(
                                    context,
                                    false,
                                    this,
                                    BluetoothDevice.TRANSPORT_LE
                                )
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Immediate reconnect error: ${e.message}")
                }
            }

            handler.post { connectionStateCallback?.invoke(false) }
            return
        }

        when (newState) {
            BluetoothProfile.STATE_CONNECTED -> {
                isConnected = true
                isReconnecting = false
                isManualDisconnect = false
                connectionAttempts = 0
                Log.i(TAG, "Connected to GATT server")

                handler.post { connectionStateCallback?.invoke(true) }
                
                deviceAddress?.let { address ->
                    handler.post { connectionSuccessCallback?.invoke(address) }
                }

                handler.post {
                    try {
                        gatt.discoverServices()
                    } catch (e: Exception) {
                        Log.e(TAG, "Service discovery failed: ${e.message}")
                    }
                }
            }

            BluetoothProfile.STATE_DISCONNECTED -> {
                isConnected = false
                isReconnecting = false
                Log.i(TAG, "Disconnected from GATT server, manual=$isManualDisconnect")

                handler.post { 
                    connectionStateCallback?.invoke(false)
                    if (!isManualDisconnect) {
                        connectionLostCallback?.invoke()
                    }
                }

                if (!deviceAddress.isNullOrBlank() && autoReconnect && highFrequencyReconnect && !isManualDisconnect) {
                    startHighFrequencyReconnect(deviceAddress!!)
                } else if (isManualDisconnect) {
                    Log.d(TAG, "Manual disconnect - no auto reconnect")
                }
            }
        }
    }


    private val dataBuffer = StringBuilder()
    private val maxBufferSize = 1024 * 1024
    private var lastDataTime = 0L


    @Suppress("DEPRECATION")
    override fun onCharacteristicChanged(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic
    ) {
        super.onCharacteristicChanged(gatt, characteristic)

        @Suppress("DEPRECATION")
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

        if (lastDataTime > 0) {
            val timeDiff = currentTime - lastDataTime
            if (timeDiff > 10000) {
                Log.w(TAG, "Long data gap: ${timeDiff / 1000}s")
            }
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
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                    val writeResult = gatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                                    Log.d(TAG, "Descriptor write result=$writeResult")
                                } else {
                                    @Suppress("DEPRECATION")
                                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                                    @Suppress("DEPRECATION")
                                    val writeResult = gatt.writeDescriptor(descriptor)
                                    Log.d(TAG, "Descriptor write result=$writeResult")
                                }
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
        handler.post {
            statusCallback?.let { callback ->
                getStatus(callback)
            }
        }
    }
    
    fun setAutoReconnect(enabled: Boolean) {
        autoReconnect = enabled
        Log.d(TAG, "Auto reconnect set to: $enabled")
    }
    
    fun setHighFrequencyReconnect(enabled: Boolean) {
        highFrequencyReconnect = enabled
        if (!enabled) {
            stopHighFrequencyReconnect()
        }
        Log.d(TAG, "High frequency reconnect set to: $enabled")
    }
    
    fun setConnectionLostCallback(callback: (() -> Unit)?) {
        connectionLostCallback = callback
    }
    
    fun setConnectionSuccessCallback(callback: ((String) -> Unit)?) {
        connectionSuccessCallback = callback
    }
    
    fun setSpecifiedDeviceAddress(address: String?) {
        specifiedDeviceAddress = address
        Log.d(TAG, "Set specified device address: $address")
    }
    
    fun getSpecifiedDeviceAddress(): String? = specifiedDeviceAddress
    
    fun setDialogOpen(isOpen: Boolean) {
        isDialogOpen = isOpen
        Log.d(TAG, "Dialog open state set to: $isOpen")
    }

    fun setAutoConnectBlocked(blocked: Boolean) {
        isAutoConnectBlocked = blocked
        Log.d(TAG, "Auto connect blocked set to: $blocked")
    }
    
    fun resetManualDisconnectState() {
        isManualDisconnect = false
        isAutoConnectBlocked = false
        Log.d(TAG, "Manual disconnect state reset - auto reconnect enabled")
    }
    
    fun setTargetDeviceAddress(address: String?) {
        targetDeviceAddress = address
        Log.d(TAG, "Set target device address: $address")
    }
    
    fun getTargetDeviceAddress(): String? = targetDeviceAddress
    
    private fun startHighFrequencyReconnect(address: String) {
        stopHighFrequencyReconnect()
        
        Log.d(TAG, "Starting high frequency reconnect for: $address")
        
        reconnectRunnable = Runnable {
            if (!isConnected && autoReconnect && highFrequencyReconnect) {
                Log.d(TAG, "High frequency reconnect attempt ${connectionAttempts + 1} for: $address")
                connect(address, connectionStateCallback)
                
                if (!isConnected) {
                    val delay = when {
                        connectionAttempts < 10 -> 100L
                        connectionAttempts < 30 -> 200L
                        connectionAttempts < 60 -> 500L
                        else -> 1000L
                    }
                    
                    reconnectHandler.postDelayed(reconnectRunnable!!, delay)
                }
            }
        }
        
        reconnectHandler.post(reconnectRunnable!!)
    }
    
    private fun stopHighFrequencyReconnect() {
        reconnectRunnable?.let {
            reconnectHandler.removeCallbacks(it)
            reconnectRunnable = null
            Log.d(TAG, "Stopped high frequency reconnect")
        }
    }
    
    fun getConnectionAttempts(): Int = connectionAttempts
    
    fun getLastKnownDeviceAddress(): String? = lastKnownDeviceAddress
    
    @SuppressLint("MissingPermission")
    fun disconnectAndCleanup() {
        isConnected = false
        autoReconnect = false
        highFrequencyReconnect = false
        isManualDisconnect = false
        isAutoConnectBlocked = false
        stopHighFrequencyReconnect()
        stopScan()
        
        bluetoothGatt?.let { gatt ->
            try {
                gatt.disconnect()
                Thread.sleep(200)
                gatt.close()
                Log.d(TAG, "GATT connection cleaned up")
            } catch (e: Exception) {
                Log.e(TAG, "Cleanup error: ${e.message}")
            }
        }
        bluetoothGatt = null
        bluetoothLeScanner = null
        deviceAddress = null
        connectionAttempts = 0
        
        dataBuffer.clear()
        connectionStateCallback = null
        statusCallback = null
        trainInfoCallback = null
        connectionLostCallback = null
        connectionSuccessCallback = null
        
        Log.d(TAG, "BLE client fully disconnected and cleaned up")
    }
}
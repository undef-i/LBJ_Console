package org.noxylva.lbjconsole

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import java.io.File
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.osmdroid.config.Configuration
import org.noxylva.lbjconsole.model.TrainRecord
import org.noxylva.lbjconsole.model.TrainRecordManager
import org.noxylva.lbjconsole.ui.screens.HistoryScreen
import org.noxylva.lbjconsole.ui.screens.MapScreen
import org.noxylva.lbjconsole.ui.screens.SettingsScreen
import org.noxylva.lbjconsole.ui.theme.LBJReceiverTheme
import org.noxylva.lbjconsole.util.LocoInfoUtil
import java.util.*
import androidx.lifecycle.lifecycleScope
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult

class MainActivity : ComponentActivity() {
    private val TAG = "MainActivity"
    private val bleClient by lazy { BLEClient(this) }
    private val trainRecordManager by lazy { TrainRecordManager(this) }
    private val locoInfoUtil by lazy { LocoInfoUtil(this) }
    
    
    private var deviceStatus by mutableStateOf("未连接")
    private var deviceAddress by mutableStateOf("")
    private var isScanning by mutableStateOf(false)
    private var foundDevices by mutableStateOf(listOf<BluetoothDevice>())
    private var scanResults = mutableListOf<ScanResult>()
    private var currentTab by mutableStateOf(0)
    private var showConnectionDialog by mutableStateOf(false)
    private var lastUpdateTime by mutableStateOf<Date?>(null)
    private var latestRecord by mutableStateOf<TrainRecord?>(null)
    private var recentRecords by mutableStateOf<List<TrainRecord>>(emptyList())
    
    
    private var filterTrain by mutableStateOf("")
    private var filterRoute by mutableStateOf("")
    private var filterDirection by mutableStateOf("全部")
    
    
    private var settingsDeviceName by mutableStateOf("LBJReceiver") 
    private var temporaryStatusMessage by mutableStateOf<String?>(null)
    
    
    private var historyEditMode by mutableStateOf(false)
    private var historySelectedRecords by mutableStateOf<Set<String>>(emptySet())
    private var historyExpandedStates by mutableStateOf<Map<String, Boolean>>(emptyMap())
    private var historyScrollPosition by mutableStateOf(0)
    private var historyScrollOffset by mutableStateOf(0)
    private var mapCenterPosition by mutableStateOf<Pair<Double, Double>?>(null)
    private var mapZoomLevel by mutableStateOf(10.0)
    private var mapRailwayLayerVisible by mutableStateOf(true) 
    
    
    private var targetDeviceName = "LBJReceiver"
    
    
    private val settingsPrefs by lazy { getSharedPreferences("app_settings", Context.MODE_PRIVATE) }
    
    private fun getAppVersion(): String {
        return try {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            packageInfo.versionName ?: "Unknown"
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get app version", e)
            "Unknown"
        }
    } 
    
    
    private val requestPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        
        val bluetoothPermissionsGranted = permissions.filter { it.key.contains("BLUETOOTH") }.all { it.value }
        val locationPermissionsGranted = permissions.filter { it.key.contains("LOCATION") }.all { it.value }
        
        if (bluetoothPermissionsGranted && locationPermissionsGranted) {
            Log.d(TAG, "Permissions granted, starting auto scan and connect")
            startAutoScanAndConnect()
        } else {
            Log.e(TAG, "Missing permissions: $permissions")
            deviceStatus = "需要蓝牙和位置权限"
        }
    }

    
    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val deviceName = device.name ?: "未知设备"
            val deviceAddress = device.address
            
            Log.d(TAG, "Found device name=$deviceName address=$deviceAddress")
            
            val existingDevice = scanResults.find { it.device.address == deviceAddress }
            if (existingDevice == null) {
                scanResults.add(result)
                updateDeviceList()
                
                
                if (deviceName == targetDeviceName) {
                    Log.d(TAG, "Found target=$targetDeviceName, connecting")
                    bleClient.stopScan()
                    connectToDevice(device)
                    showConnectionDialog = false
                }
            }
        }
        
        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE scan failed code=$errorCode")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        
        loadSettings()
        
        
        val permissions = mutableListOf<String>()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.addAll(arrayOf(
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_ADVERTISE
            ))
        } else {
            permissions.addAll(arrayOf(
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN
            ))
        }
        
        permissions.addAll(arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ))
        
        requestPermissions.launch(permissions.toTypedArray())
        
        
        bleClient.setTrainInfoCallback { jsonData ->
            handleTrainInfo(jsonData)
        }
        
        
        lifecycleScope.launch {
            try {
                locoInfoUtil.loadLocoData()
                Log.d(TAG, "Loaded locomotive data")
            } catch (e: Exception) {
                Log.e(TAG, "Load locomotive data failed", e)
            }
        }
        
        
        try {
            
            val osmCacheDir = File(cacheDir, "osm").apply { mkdirs() }
            val tileCache = File(osmCacheDir, "tiles").apply { mkdirs() }
            
            
            Configuration.getInstance().apply {
                userAgentValue = packageName
                load(this@MainActivity, getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
                osmdroidBasePath = osmCacheDir
                osmdroidTileCache = tileCache
                expirationOverrideDuration = 86400000L * 7 
                tileDownloadThreads = 2
                tileFileSystemThreads = 2
                
                setUserAgentValue("LBJReceiver/1.0")
            }
            
            Log.d(TAG, "OSM cache configured")
        } catch (e: Exception) {
            Log.e(TAG, "OSM cache config failed", e)
        }
        
        saveSettings()
        
        enableEdgeToEdge()
        setContent {
            LBJReceiverTheme {
                val scope = rememberCoroutineScope()
                
                Surface(modifier = Modifier.fillMaxSize()) {
                    MainContent(
                        deviceStatus = deviceStatus,
                        isConnected = bleClient.isConnected(),
                        isScanning = isScanning,
                        currentTab = currentTab,
                        onTabChange = { tab -> 
                            currentTab = tab
                            saveSettings()
                        },
                        onConnectClick = { showConnectionDialog = true },
                        
                        
                        latestRecord = latestRecord,
                        recentRecords = recentRecords,
                        lastUpdateTime = lastUpdateTime,
                        temporaryStatusMessage = temporaryStatusMessage,
                        onRecordClick = { record ->
                            Log.d(TAG, "Record clicked train=${record.train}")
                        },
                        onClearMonitorLog = {
                            recentRecords = emptyList()
                            temporaryStatusMessage = null
                        },
                        
                        
                        allRecords = if (trainRecordManager.getFilteredRecords().isNotEmpty())
                            trainRecordManager.getFilteredRecords() else trainRecordManager.getAllRecords(),
                        recordCount = trainRecordManager.getRecordCount(),
                        filterTrain = filterTrain,
                        filterRoute = filterRoute,
                        filterDirection = filterDirection,
                        
                        
                        historyEditMode = historyEditMode,
                        historySelectedRecords = historySelectedRecords,
                        historyExpandedStates = historyExpandedStates,
                        historyScrollPosition = historyScrollPosition,
                        historyScrollOffset = historyScrollOffset,
                        onHistoryStateChange = { editMode, selectedRecords, expandedStates, scrollPosition, scrollOffset ->
                            historyEditMode = editMode
                            historySelectedRecords = selectedRecords
                            historyExpandedStates = expandedStates
                            historyScrollPosition = scrollPosition
                            historyScrollOffset = scrollOffset
                            saveSettings()
                        },
                        
                        
                        mapCenterPosition = mapCenterPosition,
                        mapZoomLevel = mapZoomLevel,
                        mapRailwayLayerVisible = mapRailwayLayerVisible,
                        onMapStateChange = { centerPos, zoomLevel, railwayVisible ->
                            mapCenterPosition = centerPos
                            mapZoomLevel = zoomLevel
                            mapRailwayLayerVisible = railwayVisible
                            saveSettings()
                        },
                        onFilterChange = { train, route, direction ->
                            filterTrain = train
                            filterRoute = route
                            filterDirection = direction
                            trainRecordManager.setFilter(train, route, direction)
                        },
                        onClearFilter = {
                            filterTrain = ""
                            filterRoute = ""
                            filterDirection = "全部"
                            trainRecordManager.clearFilter()
                        },
                        onClearRecords = {
                            scope.launch {
                                trainRecordManager.clearRecords()
                                recentRecords = emptyList()
                                latestRecord = null
                                temporaryStatusMessage = null
                            }
                        },

                        onDeleteRecords = { records ->
                            scope.launch {
                                val deletedCount = trainRecordManager.deleteRecords(records)
                                if (deletedCount > 0) {
                                    Toast.makeText(
                                        this@MainActivity,
                                        "已删除 $deletedCount 条记录",
                                        Toast.LENGTH_SHORT
                                    ).show()
                                    
                                    if (records.contains(latestRecord)) {
                                        latestRecord = null
                                    }
                                }
                            }
                        },

                        
                        deviceName = settingsDeviceName,
                        onDeviceNameChange = { newName -> settingsDeviceName = newName },
                        onApplySettings = {
                            saveSettings()
                            targetDeviceName = settingsDeviceName
                            Toast.makeText(this, "设备名称 '${settingsDeviceName}' 已保存，下次连接时生效", Toast.LENGTH_LONG).show()
                            Log.d(TAG, "Applied settings deviceName=${settingsDeviceName}")
                        },
                        appVersion = getAppVersion(),
                        locoInfoUtil = locoInfoUtil
                    )
                    
                    if (showConnectionDialog) {
                        ConnectionDialog(
                            isScanning = isScanning,
                            devices = foundDevices,
                            onDismiss = { 
                                showConnectionDialog = false
                                stopScan()
                            },
                            onScan = {
                                if (isScanning) {
                                    stopScan()
                                } else {
                                    startScan()
                                }
                            },
                            onConnect = { device ->
                                showConnectionDialog = false
                                connectToDevice(device)
                            }
                        )
                    }
                }
            }
        }
    }
    
    
    private fun connectToDevice(device: BluetoothDevice) {
        deviceStatus = "正在连接..."
        Log.d(TAG, "Connecting to device name=${device.name ?: "Unknown"} address=${device.address}")
        
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val bluetoothAdapter = bluetoothManager.adapter
        if (bluetoothAdapter == null || bluetoothAdapter.isEnabled != true) {
            deviceStatus = "蓝牙未启用"
            Log.e(TAG, "Bluetooth adapter unavailable or disabled")
            return
        }
        
        bleClient.connect(device.address) { connected ->
            runOnUiThread {
                if (connected) {
                    deviceStatus = "已连接"
                    temporaryStatusMessage = null
                    Log.d(TAG, "Connected to device name=${device.name ?: "Unknown"}")
                } else {
                    deviceStatus = "连接失败，正在重试..."
                    Log.e(TAG, "Connection failed, auto-retry enabled for name=${device.name ?: "Unknown"}")
                }
            }
        }
        
        deviceAddress = device.address
    }
    
    
    private fun handleTrainInfo(jsonData: JSONObject) {
        Log.d(TAG, "Received train data=${jsonData.toString().take(50)}...")
        
        runOnUiThread {
            try {
                val isTestData = jsonData.optBoolean("test_flag", false) 
                lastUpdateTime = Date()
                temporaryStatusMessage = null

                if (isTestData) {
                    Log.i(TAG, "Received keep-alive signal")
                    forceUiRefresh() 
                } else {
                    temporaryStatusMessage = null 
                    
                    val record = trainRecordManager.addRecord(jsonData) 
                    Log.d(TAG, "Added record train=${record.train} direction=${record.direction}")

                    
                    latestRecord = record
                    
                    val newList = mutableListOf<TrainRecord>()
                    newList.add(record)
                    newList.addAll(recentRecords.filterNot { it.train == record.train && it.time == record.time }) 
                    recentRecords = newList.take(10)

                    Log.d(TAG, "Updated UI train=${record.train}")
                    forceUiRefresh()
                }

            } catch (e: Exception) {
                Log.e(TAG, "Train data error: ${e.message}")
                e.printStackTrace()
                temporaryStatusMessage = null 
                
                forceUiRefresh()
            }
        }
    }
    
    
    private fun forceUiRefresh() {
        Log.d(TAG, "Refreshing UI train=${latestRecord?.train}")
    }
    
    


    
    private fun updateTemporaryStatusMessage(message: String) {
        temporaryStatusMessage = message

    }

    
    private fun startAutoScanAndConnect() {
        Log.d(TAG, "Starting auto scan and connect")
        
        if (!hasBluetoothPermissions()) {
            Log.e(TAG, "Missing bluetooth permissions for auto scan")
            deviceStatus = "需要蓝牙和位置权限"
            return
        }
        
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val bluetoothAdapter = bluetoothManager.adapter
        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth adapter unavailable")
            deviceStatus = "设备不支持蓝牙"
            return
        }
        
        if (!bluetoothAdapter.isEnabled) {
            Log.e(TAG, "Bluetooth adapter disabled")
            deviceStatus = "请启用蓝牙"
            return
        }
        
        bleClient.setAutoReconnect(true)
        
        val targetDeviceName = if (settingsDeviceName.isNotBlank() && settingsDeviceName != "LBJReceiver") {
            settingsDeviceName
        } else {
            "LBJReceiver"
        }
        
        Log.d(TAG, "Auto scanning for target device: $targetDeviceName")
        deviceStatus = "正在自动扫描连接..."
        
        bleClient.scanDevices(targetDeviceName) { device ->
            val deviceName = device.name ?: "Unknown"
            Log.d(TAG, "Auto scan found device: $deviceName")
            
            if (deviceName.equals(targetDeviceName, ignoreCase = true)) {
                Log.d(TAG, "Found target device, auto connecting to: $deviceName")
                bleClient.stopScan()
                connectToDevice(device)
            }
        }
    }
    
    private fun startScan() {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val bluetoothAdapter = bluetoothManager.adapter
        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth adapter unavailable")
            deviceStatus = "设备不支持蓝牙"
            return
        }
        
        if (!bluetoothAdapter.isEnabled) {
            Log.e(TAG, "Bluetooth adapter disabled")
            deviceStatus = "请启用蓝牙"
            return
        }
        
        bleClient.setAutoReconnect(true)
        
        isScanning = true
        foundDevices = emptyList()
        val targetDeviceName = if (settingsDeviceName.isNotBlank() && settingsDeviceName != "LBJReceiver") {
            settingsDeviceName
        } else {
            null
        }
        Log.d(TAG, "Starting continuous BLE scan target=${targetDeviceName ?: "Any"} (settings=${settingsDeviceName})")
        
        bleClient.scanDevices(targetDeviceName) { device ->
            if (!foundDevices.any { it.address == device.address }) {
                Log.d(TAG, "Found device name=${device.name ?: "Unknown"} address=${device.address}")
                foundDevices = foundDevices + device
            }
        }
    }

    
    private fun stopScan() {
        isScanning = false
        bleClient.stopScan()
        Log.d(TAG, "Stopped BLE scan")
    }
    
    private fun hasBluetoothPermissions(): Boolean {
        val bluetoothPermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_ADMIN) == PackageManager.PERMISSION_GRANTED
        }
        
        val locationPermissions = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        
        return bluetoothPermissions && locationPermissions
    }

    
    private fun updateDeviceList() {
        foundDevices = scanResults.map { it.device }
    }
    
    
    private fun loadSettings() {
        settingsDeviceName = settingsPrefs.getString("device_name", "LBJReceiver") ?: "LBJReceiver"
        targetDeviceName = settingsDeviceName
        
        
        currentTab = settingsPrefs.getInt("current_tab", 0)
        historyEditMode = settingsPrefs.getBoolean("history_edit_mode", false)
        
        val selectedRecordsStr = settingsPrefs.getString("history_selected_records", "")
        historySelectedRecords = if (selectedRecordsStr.isNullOrEmpty()) {
            emptySet()
        } else {
            selectedRecordsStr.split(",").toSet()
        }
        
        val expandedStatesStr = settingsPrefs.getString("history_expanded_states", "")
        historyExpandedStates = if (expandedStatesStr.isNullOrEmpty()) {
            emptyMap()
        } else {
            expandedStatesStr.split(";").mapNotNull { pair ->
                val parts = pair.split(":")
                if (parts.size == 2) parts[0] to (parts[1] == "true") else null
            }.toMap()
        }
        
        historyScrollPosition = settingsPrefs.getInt("history_scroll_position", 0)
        historyScrollOffset = settingsPrefs.getInt("history_scroll_offset", 0)
        
        val centerLat = settingsPrefs.getFloat("map_center_lat", Float.NaN)
        val centerLon = settingsPrefs.getFloat("map_center_lon", Float.NaN)
        mapCenterPosition = if (!centerLat.isNaN() && !centerLon.isNaN()) {
            centerLat.toDouble() to centerLon.toDouble()
        } else null
        
        mapZoomLevel = settingsPrefs.getFloat("map_zoom_level", 10.0f).toDouble()
        mapRailwayLayerVisible = settingsPrefs.getBoolean("map_railway_visible", true)
        
        Log.d(TAG, "Loaded settings deviceName=${settingsDeviceName} tab=${currentTab}")
    }
    
    
    private fun saveSettings() {
        val editor = settingsPrefs.edit()
            .putString("device_name", settingsDeviceName)
            .putInt("current_tab", currentTab)
            .putBoolean("history_edit_mode", historyEditMode)
            .putString("history_selected_records", historySelectedRecords.joinToString(","))
            .putString("history_expanded_states", historyExpandedStates.map { "${it.key}:${it.value}" }.joinToString(";"))
            .putInt("history_scroll_position", historyScrollPosition)
            .putInt("history_scroll_offset", historyScrollOffset)
            .putFloat("map_zoom_level", mapZoomLevel.toFloat())
            .putBoolean("map_railway_visible", mapRailwayLayerVisible)
            
        mapCenterPosition?.let { (lat, lon) ->
            editor.putFloat("map_center_lat", lat.toFloat())
            editor.putFloat("map_center_lon", lon.toFloat())
        }
        
        editor.apply()
        Log.d(TAG, "Saved settings deviceName=${settingsDeviceName} tab=${currentTab} mapCenter=${mapCenterPosition} zoom=${mapZoomLevel}")
    }
    
    override fun onResume() {
        super.onResume()
        Log.d(TAG, "App resumed")
        
        if (hasBluetoothPermissions() && !bleClient.isConnected()) {
            Log.d(TAG, "App resumed and not connected, starting auto scan")
            startAutoScanAndConnect()
        }
    }
    
    override fun onPause() {
        super.onPause()
        saveSettings()
        Log.d(TAG, "App paused, settings saved")
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainContent(
    deviceStatus: String,
    isConnected: Boolean,
    isScanning: Boolean,
    currentTab: Int,
    onTabChange: (Int) -> Unit,
    onConnectClick: () -> Unit,
    
    
    latestRecord: TrainRecord?,
    recentRecords: List<TrainRecord>,
    lastUpdateTime: Date?,
    temporaryStatusMessage: String? = null,
    onRecordClick: (TrainRecord) -> Unit,
    onClearMonitorLog: () -> Unit,
    
    
    allRecords: List<TrainRecord>,
    recordCount: Int,
    filterTrain: String,
    filterRoute: String,
    filterDirection: String,
    onFilterChange: (String, String, String) -> Unit,
    onClearFilter: () -> Unit,
    onClearRecords: () -> Unit,

    onDeleteRecords: (List<TrainRecord>) -> Unit,

    
    deviceName: String,
    onDeviceNameChange: (String) -> Unit,
    onApplySettings: () -> Unit,
    appVersion: String,

    
    locoInfoUtil: LocoInfoUtil,
    
    
    historyEditMode: Boolean,
    historySelectedRecords: Set<String>,
    historyExpandedStates: Map<String, Boolean>,
    historyScrollPosition: Int,
    historyScrollOffset: Int,
    onHistoryStateChange: (Boolean, Set<String>, Map<String, Boolean>, Int, Int) -> Unit,
    
    
    mapCenterPosition: Pair<Double, Double>?,
    mapZoomLevel: Double,
    mapRailwayLayerVisible: Boolean,
    onMapStateChange: (Pair<Double, Double>?, Double, Boolean) -> Unit
) {
    val statusColor = if (isConnected) Color(0xFF4CAF50) else Color(0xFFFF5722)
    
    
    val timeSinceLastUpdate = remember { mutableStateOf<String?>(null) }
    LaunchedEffect(key1 = lastUpdateTime) {
        if (lastUpdateTime != null) {
            while (true) {
                val now = Date()
                val diffInSec = (now.time - lastUpdateTime.time) / 1000
                timeSinceLastUpdate.value = when {
                    diffInSec < 60 -> "${diffInSec}秒前"
                    diffInSec < 3600 -> "${diffInSec / 60}分钟前"
                    else -> "${diffInSec / 3600}小时前"
                }
                val updateInterval = if (diffInSec < 60) 500L else if (diffInSec < 3600) 30000L else 300000L
                delay(updateInterval)
            }
        } else {
            timeSinceLastUpdate.value = null
        }
    }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("LBJ Console") },
                actions = {
                    
                    timeSinceLastUpdate.value?.let { time ->
                        Text(
                            text = time,
                            modifier = Modifier.padding(end = 8.dp),
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .background(
                                color = statusColor,
                                shape = CircleShape
                            )
                    )
                    
                    Spacer(modifier = Modifier.width(8.dp))
                    
                    IconButton(onClick = onConnectClick) {
                        Icon(
                            imageVector = Icons.Default.Bluetooth,
                            contentDescription = "连接蓝牙设备"
                        )
                    }
                }
            )
        },
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = currentTab == 0,
                    onClick = { onTabChange(0) },
                    icon = { Icon(Icons.Filled.DirectionsRailway, "记录") },
                    label = { Text("列车记录") }
                )
                
                NavigationBarItem(
                    selected = currentTab == 3,
                    onClick = { onTabChange(3) },
                    icon = { Icon(Icons.Filled.LocationOn, "地图") },
                    label = { Text("位置地图") }
                )
                
                NavigationBarItem(
                    selected = currentTab == 2,
                    onClick = { onTabChange(2) },
                    icon = { Icon(Icons.Filled.Settings, "设置") },
                    label = { Text("设置") }
                )
            }
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            when (currentTab) {
                0 -> HistoryScreen(
                    records = allRecords,
                    latestRecord = latestRecord,
                    lastUpdateTime = lastUpdateTime,
                    temporaryStatusMessage = temporaryStatusMessage,
                    locoInfoUtil = locoInfoUtil,
                    onClearRecords = onClearRecords,

                    onRecordClick = onRecordClick,
                    onClearLog = onClearMonitorLog,
                    onDeleteRecords = onDeleteRecords,
                    editMode = historyEditMode,
                    selectedRecords = historySelectedRecords,
                    expandedStates = historyExpandedStates,
                    scrollPosition = historyScrollPosition,
                    scrollOffset = historyScrollOffset,
                    onStateChange = onHistoryStateChange
                )
                2 -> SettingsScreen(
                    deviceName = deviceName,
                    onDeviceNameChange = onDeviceNameChange,
                    onApplySettings = onApplySettings,
                    appVersion = appVersion
                )
                3 -> MapScreen(
                    records = if (allRecords.isNotEmpty()) allRecords else recentRecords,
                    centerPosition = mapCenterPosition,
                    zoomLevel = mapZoomLevel,
                    railwayLayerVisible = mapRailwayLayerVisible,
                    onStateChange = onMapStateChange
                )
            }
        }
    }
}

@Composable
fun ConnectionDialog(
    isScanning: Boolean,
    devices: List<BluetoothDevice>,
    onDismiss: () -> Unit,
    onScan: () -> Unit,
    onConnect: (BluetoothDevice) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("连接设备") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                Button(
                    onClick = onScan,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(if (isScanning) "停止扫描" else "扫描设备")
                }
                
                Spacer(modifier = Modifier.height(8.dp))
                
                if (isScanning) {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    Spacer(modifier = Modifier.height(8.dp))
                }
                
                if (devices.isEmpty()) {
                    Text("未找到设备")
                } else {
                    Column {
                        devices.forEach { device ->
                            Card(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp)
                                    .clickable { onConnect(device) }
                            ) {
                                Column(
                                    modifier = Modifier.padding(8.dp)
                                ) {
                                    Text(
                                        text = device.name ?: "未知设备",
                                        fontWeight = FontWeight.Bold
                                    )
                                    Text(
                                        text = device.address,
                                        style = MaterialTheme.typography.bodySmall
                                    )
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("取消")
            }
        }
    )
}


fun Date.toSimpleFormat(): String {
    val sdf = java.text.SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    return sdf.format(this)
}
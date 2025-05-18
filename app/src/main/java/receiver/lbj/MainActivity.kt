package receiver.lbj

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.content.Intent
import java.io.File
import android.net.Uri
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.osmdroid.config.Configuration
import receiver.lbj.model.TrainRecord
import receiver.lbj.model.TrainRecordManager
import receiver.lbj.ui.screens.HistoryScreen
import receiver.lbj.ui.screens.MapScreen
import receiver.lbj.ui.screens.SettingsScreen
import receiver.lbj.ui.screens.MapScreen
import receiver.lbj.ui.theme.LBJReceiverTheme
import receiver.lbj.util.LocoInfoUtil
import java.util.*
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewModelScope
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
    
    
    private var targetDeviceName = "LBJReceiver" 
    
    
    private val requestPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        
        val bluetoothPermissionsGranted = permissions.filter { it.key.contains("BLUETOOTH") }.all { it.value }
        val locationPermissionsGranted = permissions.filter { it.key.contains("LOCATION") }.all { it.value }
        
        if (bluetoothPermissionsGranted && locationPermissionsGranted) {
            Log.d(TAG, "Permissions granted")
            
            startScan()
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
        
        
        requestPermissions.launch(arrayOf(
            Manifest.permission.BLUETOOTH,
            Manifest.permission.BLUETOOTH_ADMIN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
            Manifest.permission.READ_EXTERNAL_STORAGE
        ))
        
        
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
                        onTabChange = { tab -> currentTab = tab },
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
                        onExportRecords = {
                            scope.launch {
                                exportRecordsToCSV()
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
                            
                            
                            Toast.makeText(this, "设备名称 '${settingsDeviceName}' 已保存，下次连接时生效", Toast.LENGTH_LONG).show()
                            Log.d(TAG, "Applied settings deviceName=${settingsDeviceName}")
                        },
                        locoInfoUtil = locoInfoUtil
                    )
                    
                    


                }
            }
        }
    }
    
    
    private fun connectToDevice(device: BluetoothDevice) {
        deviceStatus = "正在连接..."
        Log.d(TAG, "Connecting to device name=${device.name ?: "Unknown"} address=${device.address}")
        
        bleClient.connect(device.address) { connected ->
            if (connected) {
                deviceStatus = "已连接"
                Log.d(TAG, "Connected to device name=${device.name ?: "Unknown"}")
            } else {
                deviceStatus = "连接失败或已断开连接"
                Log.e(TAG, "Connection failed name=${device.name ?: "Unknown"}")
            }
        }
        
        deviceAddress = device.address
        stopScan()
    }
    
    
    private fun handleTrainInfo(jsonData: JSONObject) {
        Log.d(TAG, "Received train data=${jsonData.toString().take(50)}...")
        
        runOnUiThread {
            try {
                val isTestData = jsonData.optBoolean("test_flag", false) 
                lastUpdateTime = Date() 

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
    
    
    private fun exportRecordsToCSV() {
        val records = trainRecordManager.getFilteredRecords()
        val file = trainRecordManager.exportToCsv(records)
        if (file != null) {
            try {
                
                val uri = FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.provider",
                    file
                )
                val intent = Intent(Intent.ACTION_SEND)
                intent.type = "text/csv"
                intent.putExtra(Intent.EXTRA_STREAM, uri)
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                startActivity(Intent.createChooser(intent, "分享CSV文件"))
            } catch (e: Exception) {
                Log.e(TAG, "CSV export failed: ${e.message}")
                Toast.makeText(this, "导出失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        } else {
            Toast.makeText(this, "导出CSV文件失败", Toast.LENGTH_SHORT).show()
        }
    }

    
    private fun updateTemporaryStatusMessage(message: String) {
        temporaryStatusMessage = message
        
        Handler(Looper.getMainLooper()).postDelayed({
            if (temporaryStatusMessage == message) {
                temporaryStatusMessage = null
            }
        }, 3000)
    }

    
    private fun startScan() {
        isScanning = true
        foundDevices = emptyList()
        val targetDeviceName = settingsDeviceName.ifBlank { null } 
        Log.d(TAG, "Starting BLE scan target=${targetDeviceName ?: "Any"}")
        
        bleClient.scanDevices(targetDeviceName) { device ->
            if (!foundDevices.any { it.address == device.address }) {
                Log.d(TAG, "Found device name=${device.name ?: "Unknown"} address=${device.address}")
                foundDevices = foundDevices + device
                
                if (targetDeviceName != null && device.name == targetDeviceName) {
                    Log.d(TAG, "Found target=$targetDeviceName, connecting")
                    stopScan() 
                    connectToDevice(device) 
                } else if (!foundDevices.any { it.address == device.address }) {
                    showConnectionDialog = true 
                }
            }
        }
    }

    
    private fun stopScan() {
        isScanning = false
        bleClient.stopScan()
        Log.d(TAG, "Stopped BLE scan")
    }

    
    private fun updateDeviceList() {
        foundDevices = scanResults.map { it.device }
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
    onExportRecords: () -> Unit,
    onDeleteRecords: (List<TrainRecord>) -> Unit,

    
    deviceName: String,
    onDeviceNameChange: (String) -> Unit,
    onApplySettings: () -> Unit,

    
    locoInfoUtil: LocoInfoUtil
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
                delay(1000) 
            }
        } else {
            timeSinceLastUpdate.value = null
        }
    }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("LBJReceiver") },
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
                    onExportRecords = onExportRecords,
                    onRecordClick = onRecordClick,
                    onClearLog = onClearMonitorLog,
                    onDeleteRecords = onDeleteRecords
                )
                2 -> SettingsScreen(
                    deviceName = deviceName,
                    onDeviceNameChange = onDeviceNameChange,
                    onApplySettings = onApplySettings,
                )
                3 -> MapScreen(
                    records = if (allRecords.isNotEmpty()) allRecords else recentRecords,
                    onCenterMap = {}
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
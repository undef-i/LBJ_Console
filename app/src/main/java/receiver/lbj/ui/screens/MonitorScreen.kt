package receiver.lbj.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight

import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import receiver.lbj.model.TrainRecord
import receiver.lbj.ui.components.TrainDetailDialog
import java.text.SimpleDateFormat
import java.util.*

@Composable
fun MonitorScreen(
    latestRecord: TrainRecord?,
    recentRecords: List<TrainRecord>,
    lastUpdateTime: Date?,
    temporaryStatusMessage: String? = null,
    onRecordClick: (TrainRecord) -> Unit,
    onClearLog: () -> Unit
) {
    var showDetailDialog by remember { mutableStateOf(false) }
    var selectedRecord by remember { mutableStateOf<TrainRecord?>(null) }
    
    
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
        }
    }
    
    
    Box(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Card(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(20.dp)
            ) {
                
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = timeSinceLastUpdate.value ?: "暂无数据",
                        fontSize = 14.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                
                Spacer(modifier = Modifier.height(16.dp))
                
                
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                ) {
                    if (latestRecord != null) {
                        
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(8.dp)
                                .clickable {
                                    selectedRecord = latestRecord
                                    showDetailDialog = true
                                    onRecordClick(latestRecord)
                                }
                        ) {
                            
                            val recordMap = latestRecord.toMap()
                            
                            
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    text = recordMap["train"]?.toString() ?: "",
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 20.sp,
                                    color = MaterialTheme.colorScheme.primary
                                )
                                
                                Text(
                                    text = recordMap["direction"]?.toString() ?: "",
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 16.sp,
                                    color = when(recordMap["direction"]?.toString()) {
                                        "上行" -> MaterialTheme.colorScheme.primary
                                        "下行" -> MaterialTheme.colorScheme.secondary
                                        else -> MaterialTheme.colorScheme.onSurface
                                    }
                                )
                            }
                            
                            Spacer(modifier = Modifier.height(6.dp))
                            
                            
                            if (recordMap.containsKey("time")) {
                                recordMap["time"]?.split("\n")?.forEach { timeLine ->
                                    Text(
                                        text = timeLine,
                                        fontSize = 14.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    Spacer(modifier = Modifier.height(4.dp))
                                }
                            }
                            
                            HorizontalDivider(thickness = 0.5.dp)
                            Spacer(modifier = Modifier.height(8.dp))
                            
                            
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                recordMap["speed"]?.let { speed ->
                                    Text(
                                        text = speed,
                                        fontSize = 14.sp,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                }
                                recordMap["position"]?.let { position ->
                                    Text(
                                        text = position,
                                        fontSize = 14.sp,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            
                            
                            Row(
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Column(modifier = Modifier.fillMaxWidth()) {
                                    recordMap.forEach { (key, value) ->
                                        when (key) {
                                            "timestamp", "train", "direction", "time", "speed", "position", "position_info" -> {}
                                            else -> {
                                                Text(
                                                    text = value,
                                                    fontSize = 14.sp,
                                                    color = MaterialTheme.colorScheme.onSurface
                                                )
                                                Spacer(modifier = Modifier.height(4.dp))
                                            }
                                        }
                                    }
                                    
                                    
                                    if (recordMap.containsKey("position_info")) {
                                        Spacer(modifier = Modifier.height(4.dp))
                                        Text(
                                            text = recordMap["position_info"] ?: "",
                                            fontSize = 14.sp,
                                            color = MaterialTheme.colorScheme.onSurface
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(
                                    "暂无列车信息",
                                    style = MaterialTheme.typography.titleLarge,
                                    color = MaterialTheme.colorScheme.outline
                                )
                                
                                if (lastUpdateTime != null) {
                                    Spacer(modifier = Modifier.height(8.dp))
                                    Text(
                                        "上次接收数据: ${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(lastUpdateTime)}",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.7f)
                                    )
                                }
                            }
                        }
                    }
                }
                
            }
        }
    }
    
    
    if (showDetailDialog && selectedRecord != null) {
        TrainDetailDialog(
            trainRecord = selectedRecord!!,
            onDismiss = { showDetailDialog = false }
        )
    }
}

@Composable
private fun InfoItem(
    label: String,
    value: String,
    fontSize: TextUnit = 14.sp
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
    ) {
        Text(
            text = "$label: ",
            fontWeight = FontWeight.Medium,
            fontSize = fontSize,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        
        Text(
            text = value,
            fontSize = fontSize,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
} 
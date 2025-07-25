package org.noxylva.lbjconsole.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import org.noxylva.lbjconsole.model.MergeSettings
import org.noxylva.lbjconsole.model.GroupBy
import org.noxylva.lbjconsole.model.TimeWindow
import org.noxylva.lbjconsole.SettingsActivity
import org.noxylva.lbjconsole.BackgroundService
import org.noxylva.lbjconsole.NotificationService
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.LaunchedEffect

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    deviceName: String,
    onDeviceNameChange: (String) -> Unit,
    onApplySettings: () -> Unit,
    appVersion: String = "Unknown",
    mergeSettings: MergeSettings,
    onMergeSettingsChange: (MergeSettings) -> Unit,
    scrollPosition: Int = 0,
    onScrollPositionChange: (Int) -> Unit = {},
    specifiedDeviceAddress: String? = null,
    searchOrderList: List<String> = emptyList(),
    onSpecifiedDeviceSelected: (String?) -> Unit = {}
) {
    val uriHandler = LocalUriHandler.current
    val scrollState = rememberScrollState()
    
    LaunchedEffect(scrollPosition) {
        scrollState.scrollTo(scrollPosition)
    }
    
    LaunchedEffect(scrollState.value) {
        onScrollPositionChange(scrollState.value)
    }
    
    LaunchedEffect(deviceName) {
        onApplySettings()
    }
    
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
            ),
            shape = RoundedCornerShape(16.dp)
        ) {
            Column(
                modifier = Modifier.padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Bluetooth,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        "蓝牙设备",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                
                OutlinedTextField(
                    value = deviceName,
                    onValueChange = onDeviceNameChange,
                    label = { Text("设备名称") },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Default.DeviceHub,
                            contentDescription = null
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp)
                )
                
                if (searchOrderList.isNotEmpty()) {
                    var deviceAddressExpanded by remember { mutableStateOf(false) }
                    
                    ExposedDropdownMenuBox(
                        expanded = deviceAddressExpanded,
                        onExpandedChange = { deviceAddressExpanded = !deviceAddressExpanded }
                    ) {
                        OutlinedTextField(
                            value = specifiedDeviceAddress ?: "无",
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("指定设备地址") },
                            leadingIcon = {
                                Icon(
                                    imageVector = Icons.Default.LocationOn,
                                    contentDescription = null
                                )
                            },
                            trailingIcon = {
                                ExposedDropdownMenuDefaults.TrailingIcon(expanded = deviceAddressExpanded)
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .menuAnchor(),
                            shape = RoundedCornerShape(12.dp)
                        )
                        ExposedDropdownMenu(
                            expanded = deviceAddressExpanded,
                            onDismissRequest = { deviceAddressExpanded = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("无") },
                                onClick = {
                                    onSpecifiedDeviceSelected(null)
                                    deviceAddressExpanded = false
                                }
                            )
                            searchOrderList.forEach { address ->
                                DropdownMenuItem(
                                    text = { 
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Text(address)
                                            if (address == specifiedDeviceAddress) {
                                                Spacer(modifier = Modifier.width(8.dp))
                                                Icon(
                                                    imageVector = Icons.Default.Check,
                                                    contentDescription = "已指定",
                                                    tint = MaterialTheme.colorScheme.primary,
                                                    modifier = Modifier.size(16.dp)
                                                )
                                            }
                                        }
                                    },
                                    onClick = {
                                        onSpecifiedDeviceSelected(address)
                                        deviceAddressExpanded = false
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
            ),
            shape = RoundedCornerShape(16.dp)
        ) {
            Column(
                modifier = Modifier.padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Settings,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        "应用设置",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                
                val context = LocalContext.current
                var backgroundServiceEnabled by remember {
                    mutableStateOf(SettingsActivity.isBackgroundServiceEnabled(context))
                }
                
                val notificationService = remember { NotificationService(context) }
                var notificationEnabled by remember {
                    mutableStateOf(notificationService.isNotificationEnabled())
                }
                
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(
                            "后台保活服务",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            "保持应用在后台运行",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = backgroundServiceEnabled,
                        onCheckedChange = { enabled ->
                            backgroundServiceEnabled = enabled
                            SettingsActivity.setBackgroundServiceEnabled(context, enabled)
                            
                            if (enabled) {
                                BackgroundService.startService(context)
                            } else {
                                BackgroundService.stopService(context)
                            }
                        }
                    )
                }
                
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(
                            "LBJ消息通知",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            "实时接收列车LBJ消息通知",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = notificationEnabled,
                        onCheckedChange = { enabled ->
                            notificationEnabled = enabled
                            notificationService.setNotificationEnabled(enabled)
                        }
                    )
                }
            }
        }
        
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
            ),
            shape = RoundedCornerShape(16.dp)
        ) {
            Column(
                modifier = Modifier.padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.MergeType,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        "记录合并",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                         "启用记录合并",
                         style = MaterialTheme.typography.bodyMedium
                     )
                    Switch(
                        checked = mergeSettings.enabled,
                        onCheckedChange = { enabled ->
                            onMergeSettingsChange(mergeSettings.copy(enabled = enabled))
                        }
                    )
                }
                
                if (mergeSettings.enabled) {
                    var groupByExpanded by remember { mutableStateOf(false) }
                    var timeWindowExpanded by remember { mutableStateOf(false) }
                    
                    ExposedDropdownMenuBox(
                        expanded = groupByExpanded,
                        onExpandedChange = { groupByExpanded = !groupByExpanded }
                    ) {
                        OutlinedTextField(
                            value = mergeSettings.groupBy.displayName,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("分组方式") },
                            leadingIcon = {
                                Icon(
                                    imageVector = Icons.Default.Group,
                                    contentDescription = null
                                )
                            },
                            trailingIcon = {
                                ExposedDropdownMenuDefaults.TrailingIcon(expanded = groupByExpanded)
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .menuAnchor(),
                            shape = RoundedCornerShape(12.dp)
                        )
                        ExposedDropdownMenu(
                            expanded = groupByExpanded,
                            onDismissRequest = { groupByExpanded = false }
                        ) {
                            GroupBy.values().forEach { groupBy ->
                                DropdownMenuItem(
                                    text = { Text(groupBy.displayName) },
                                    onClick = {
                                        onMergeSettingsChange(mergeSettings.copy(groupBy = groupBy))
                                        groupByExpanded = false
                                    }
                                )
                            }
                        }
                    }
                    
                    ExposedDropdownMenuBox(
                        expanded = timeWindowExpanded,
                        onExpandedChange = { timeWindowExpanded = !timeWindowExpanded }
                    ) {
                        OutlinedTextField(
                            value = mergeSettings.timeWindow.displayName,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("时间窗口") },
                            leadingIcon = {
                                Icon(
                                    imageVector = Icons.Default.Schedule,
                                    contentDescription = null
                                )
                            },
                            trailingIcon = {
                                ExposedDropdownMenuDefaults.TrailingIcon(expanded = timeWindowExpanded)
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .menuAnchor(),
                            shape = RoundedCornerShape(12.dp)
                        )
                        ExposedDropdownMenu(
                            expanded = timeWindowExpanded,
                            onDismissRequest = { timeWindowExpanded = false }
                        ) {
                            TimeWindow.values().forEach { timeWindow ->
                                DropdownMenuItem(
                                    text = { Text(timeWindow.displayName) },
                                    onClick = {
                                        onMergeSettingsChange(mergeSettings.copy(timeWindow = timeWindow))
                                        timeWindowExpanded = false
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        

        Text(
             text = "LBJ Console v$appVersion by undef-i",
             style = MaterialTheme.typography.bodySmall,
             color = MaterialTheme.colorScheme.onSurfaceVariant,
             textAlign = TextAlign.Center,
             modifier = Modifier
                 .fillMaxWidth()
                 .clip(RoundedCornerShape(12.dp))
                 .clickable {
                     uriHandler.openUri("https://github.com/undef-i/LBJ_Console")
                 }
                 .padding(12.dp)
         )
    }
}

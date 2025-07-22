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
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import org.noxylva.lbjconsole.model.MergeSettings
import org.noxylva.lbjconsole.model.GroupBy
import org.noxylva.lbjconsole.model.TimeWindow
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
    onScrollPositionChange: (Int) -> Unit = {}
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
                     uriHandler.openUri("https://github.com/undef-i")
                 }
                 .padding(12.dp)
         )
    }
}

package receiver.lbj.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.material3.TopAppBarDefaults.topAppBarColors
import androidx.compose.runtime.*
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import receiver.lbj.model.TrainRecord
import java.text.SimpleDateFormat
import java.util.*

@Composable
fun TrainRecordsList(
    records: List<TrainRecord>,
    onRecordClick: (TrainRecord) -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        if (records.isEmpty()) {
            Text(
                text = "暂无历史记录",
                modifier = Modifier.padding(16.dp),
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(vertical = 4.dp, horizontal = 8.dp)
            ) {
                items(records) { record ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 2.dp)
                            .clickable { onRecordClick(record) },
                        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(8.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            
                            Column {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        text = record.train,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 15.sp
                                    )
                                    
                                    Spacer(modifier = Modifier.width(4.dp))
                                    
                                    
                                    val directionText = when (record.direction) {
                                        1 -> "下行"
                                        3 -> "上行"
                                        else -> "未知"
                                    }
                                    
                                    val directionColor = when(record.direction) {
                                        1 -> MaterialTheme.colorScheme.secondary
                                        3 -> MaterialTheme.colorScheme.primary
                                        else -> MaterialTheme.colorScheme.onSurface
                                    }
                                    
                                    Surface(
                                        color = directionColor.copy(alpha = 0.1f),
                                        shape = MaterialTheme.shapes.small
                                    ) {
                                        Text(
                                            text = directionText,
                                            modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp),
                                            fontSize = 11.sp,
                                            color = directionColor
                                        )
                                    }
                                }
                                
                                Spacer(modifier = Modifier.height(2.dp))
                                
                                
                                Text(
                                    text = "位置: ${record.position} km",
                                    fontSize = 12.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            
                            
                            Column(
                                horizontalAlignment = Alignment.End
                            ) {
                                Text(
                                    text = "${record.speed} km/h",
                                    fontWeight = FontWeight.Medium,
                                    fontSize = 14.sp
                                )
                                
                                Spacer(modifier = Modifier.height(2.dp))
                                
                                
                                val timeStr = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(record.timestamp)
                                Text(
                                    text = timeStr,
                                    fontSize = 11.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun TrainRecordsListWithToolbar(
    records: List<TrainRecord>,
    onRecordClick: (TrainRecord) -> Unit,
    onFilterClick: () -> Unit,
    onExportClick: () -> Unit,
    onClearClick: () -> Unit,
    onDeleteRecords: (List<TrainRecord>) -> Unit,
    modifier: Modifier = Modifier
) {
    var selectedRecords by remember { mutableStateOf<MutableSet<TrainRecord>>(mutableSetOf()) }
    var selectionMode by remember { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxSize()) {
        
        @OptIn(ExperimentalMaterial3Api::class)
        Surface(
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.surface,
            tonalElevation = 3.dp,
            shadowElevation = 3.dp
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = if (selectionMode) "已选择 ${selectedRecords.size} 条" else "历史记录 (${records.size})",
                    style = MaterialTheme.typography.titleMedium
                )

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (selectionMode) {
                        TextButton(
                            onClick = {
                                if (selectedRecords.isNotEmpty()) {
                                    onDeleteRecords(selectedRecords.toList())
                                }
                                selectionMode = false
                                selectedRecords = mutableSetOf()
                            },
                            colors = ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.error
                            )
                        ) {
                            Text("删除")
                        }
                        TextButton(onClick = {
                            selectionMode = false
                            selectedRecords = mutableSetOf()
                        }) {
                            Text("取消")
                        }
                    } else {
                        IconButton(onClick = onFilterClick) {
                            Icon(
                                imageVector = Icons.Default.FilterList, 
                                contentDescription = "筛选"
                            )
                        }
                        IconButton(onClick = onExportClick) {
                            Icon(
                                imageVector = Icons.Default.Share,
                                contentDescription = "导出"
                            )
                        }
                    }
                }
            }
        }
        
        
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(vertical = 4.dp, horizontal = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            items(records.chunked(2)) { rowRecords ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    rowRecords.forEach { record ->
                        val isSelected = selectedRecords.contains(record)
                        Card(
                            modifier = Modifier
                                .weight(1f)
                                .clickable {
                                    if (selectionMode) {
                                        if (isSelected) {
                                            selectedRecords.remove(record)
                                        } else {
                                            selectedRecords.add(record)
                                        }
                                        if (selectedRecords.isEmpty()) {
                                            selectionMode = false
                                        }
                                    } else {
                                        onRecordClick(record)
                                    }
                                }
                                .padding(vertical = 2.dp),
                            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(8.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                
                                Column(modifier = Modifier.weight(1f)) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        modifier = Modifier.fillMaxWidth()
                                    ) {
                                        if (selectionMode) {
                                            Checkbox(
                                                checked = isSelected,
                                                onCheckedChange = { checked ->
                                                    if (checked) {
                                                        selectedRecords.add(record)
                                                    } else {
                                                        selectedRecords.remove(record)
                                                    }
                                                    if (selectedRecords.isEmpty()) {
                                                        selectionMode = false
                                                    }
                                                },
                                                modifier = Modifier.padding(end = 8.dp)
                                            )
                                        }
                                        
                                        Text(
                                            text = record.train,
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 15.sp,
                                            modifier = Modifier.weight(1f)
                                        )
                                        
                                        if (!selectionMode) {
                                            IconButton(
                                                onClick = {
                                                    selectionMode = true
                                                    selectedRecords = mutableSetOf(record)
                                                },
                                                modifier = Modifier.size(32.dp)
                                            ) {
                                                Icon(
                                                    imageVector = Icons.Default.Clear,
                                                    contentDescription = "删除",
                                                    modifier = Modifier.size(16.dp),
                                                    tint = MaterialTheme.colorScheme.error
                                                )
                                            }
                                        }
                                    }
                                    
                                    if (record.speed.isNotEmpty() || record.position.isNotEmpty()) {
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween
                                        ) {
                                            if (record.speed.isNotEmpty()) {
                                                Text(
                                                    text = "${record.speed} km/h",
                                                    fontSize = 12.sp,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                                )
                                            }
                                            if (record.position.isNotEmpty()) {
                                                Text(
                                                    text = "${record.position} km",
                                                    fontSize = 12.sp,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                                )
                                            }
                                        }
                                    }
                                    
                                    val timeStr = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(record.timestamp)
                                    Text(
                                        text = timeStr,
                                        fontSize = 11.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
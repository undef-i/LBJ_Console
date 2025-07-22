package org.noxylva.lbjconsole.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.ripple.rememberRipple
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import org.osmdroid.tileprovider.MapTileProviderBasic
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.tileprovider.tilesource.XYTileSource
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import org.osmdroid.views.overlay.TilesOverlay
import org.noxylva.lbjconsole.model.MergedTrainRecord
import org.noxylva.lbjconsole.model.TrainRecord
import org.noxylva.lbjconsole.util.LocoInfoUtil
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun MergedHistoryScreen(
    mergedRecords: List<MergedTrainRecord>,
    latestRecord: TrainRecord?,
    lastUpdateTime: Date?,
    temporaryStatusMessage: String? = null,
    locoInfoUtil: LocoInfoUtil? = null,
    onClearRecords: () -> Unit = {},
    onRecordClick: (TrainRecord) -> Unit = {},
    onClearLog: () -> Unit = {},
    onDeleteRecords: (List<TrainRecord>) -> Unit = {},
    onDeleteMergedRecord: (MergedTrainRecord) -> Unit = {},
    editMode: Boolean = false,
    selectedRecords: Set<String> = emptySet(),
    expandedStates: Map<String, Boolean> = emptyMap(),
    scrollPosition: Int = 0,
    scrollOffset: Int = 0,
    onStateChange: (Boolean, Set<String>, Map<String, Boolean>, Int, Int) -> Unit = { _, _, _, _, _ -> }
) {
    var isInEditMode by remember(editMode) { mutableStateOf(editMode) }
    val selectedRecordsList = remember(selectedRecords) { 
        mutableStateListOf<TrainRecord>().apply {
            addAll(mergedRecords.flatMap { it.records }.filter { 
                selectedRecords.contains(it.uniqueId) 
            })
        }
    }
    val expandedStatesMap = remember(expandedStates) { 
        mutableStateMapOf<String, Boolean>().apply { putAll(expandedStates) }
    }
    
    val listState = rememberLazyListState(
        initialFirstVisibleItemIndex = scrollPosition,
        initialFirstVisibleItemScrollOffset = scrollOffset
    )

    LaunchedEffect(isInEditMode, selectedRecordsList.size) {
        val selectedIds = selectedRecordsList.map { it.uniqueId }.toSet()
        onStateChange(isInEditMode, selectedIds, expandedStatesMap.toMap(), 
                     listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset)
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp)
                    .weight(1.0f)
            ) {
                if (mergedRecords.isEmpty()) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                "暂无合并记录",
                                style = MaterialTheme.typography.titleLarge,
                                color = MaterialTheme.colorScheme.outline
                            )
                            Text(
                                "请检查合并设置或等待更多数据",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.7f)
                            )
                        }
                    }
                } else {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(mergedRecords) { mergedRecord ->
                            MergedRecordCard(
                                mergedRecord = mergedRecord,
                                isExpanded = expandedStatesMap[mergedRecord.groupKey] == true,
                                onExpandToggle = {
                                    expandedStatesMap[mergedRecord.groupKey] = 
                                        !(expandedStatesMap[mergedRecord.groupKey] ?: false)
                                },
                                locoInfoUtil = locoInfoUtil
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MergedRecordCard(
    mergedRecord: MergedTrainRecord,
    isExpanded: Boolean,
    onExpandToggle: () -> Unit,
    locoInfoUtil: LocoInfoUtil?
) {
    val record = mergedRecord.latestRecord
    val recordMap = record.toMap(showDetailedTime = true)

    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        shape = RoundedCornerShape(8.dp)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClick = onExpandToggle,
                    interactionSource = remember { MutableInteractionSource() },
                    indication = rememberRipple(bounded = true)
                )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (recordMap.containsKey("time")) {
                        Column {
                            recordMap["time"]?.split("\n")?.forEach { timeLine ->
                                Text(
                                    text = timeLine,
                                    fontSize = 10.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                    
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = "${record.rssi} dBm",
                            fontSize = 10.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                Spacer(modifier = Modifier.height(2.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val trainDisplay = recordMap["train"]?.toString() ?: "未知列车"

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = trainDisplay,
                            fontWeight = FontWeight.Bold,
                            fontSize = 20.sp,
                            color = MaterialTheme.colorScheme.primary
                        )

                        val directionText = when (record.direction) {
                            1 -> "下"
                            3 -> "上"
                            else -> ""
                        }

                        if (directionText.isNotEmpty()) {
                            Surface(
                                shape = RoundedCornerShape(2.dp),
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.size(20.dp)
                            ) {
                                Box(
                                    modifier = Modifier.fillMaxSize(),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = directionText,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.surface,
                                        maxLines = 1,
                                        modifier = Modifier.offset(y = (-2).dp)
                                    )
                                }
                            }
                        }
                    }

                    val formattedInfo = when {
                        record.locoType.isNotEmpty() && record.loco.isNotEmpty() -> {
                            val shortLoco = if (record.loco.length > 5) {
                                record.loco.takeLast(5)
                            } else {
                                record.loco
                            }
                            "${record.locoType}-${shortLoco}"
                        }
                        record.locoType.isNotEmpty() -> record.locoType
                        record.loco.isNotEmpty() -> record.loco
                        else -> ""
                    }
                    
                    if (formattedInfo.isNotEmpty() && formattedInfo != "<NUL>") {
                        Text(
                            text = formattedInfo,
                            fontSize = 14.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    val routeStr = record.route.trim()
                    val isValidRoute = routeStr.isNotEmpty() && !routeStr.all { it == '*' }

                    val position = record.position.trim()
                    val isValidPosition = position.isNotEmpty() &&
                            !position.all { it == '-' || it == '.' } &&
                            position != "<NUL>"

                    if (isValidRoute || isValidPosition) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.height(24.dp),
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            if (isValidRoute) {
                                Text(
                                    text = "$routeStr",
                                    fontSize = 16.sp,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    modifier = Modifier.alignByBaseline()
                                )
                            }

                            if (isValidPosition) {
                                Text(
                                    text = "${position}K",
                                    fontSize = 16.sp,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    modifier = Modifier.alignByBaseline()
                                )
                            }
                        }
                    }

                    val speed = record.speed.trim()
                    val isValidSpeed = speed.isNotEmpty() &&
                            !speed.all { it == '*' || it == '-' } &&
                            speed != "NUL" &&
                            speed != "<NUL>"
                    if (isValidSpeed) {
                        Text(
                            text = "${speed} km/h",
                            fontSize = 16.sp,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }

                if (locoInfoUtil != null && record.locoType.isNotEmpty() && record.loco.isNotEmpty()) {
                    val locoInfoText = locoInfoUtil.getLocoInfoDisplay(record.locoType, record.loco)
                    if (locoInfoText != null) {
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = locoInfoText,
                            fontSize = 14.sp,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }

                if (isExpanded) {
                    Spacer(modifier = Modifier.height(12.dp))
                    Divider()
                    Spacer(modifier = Modifier.height(8.dp))
                    
                    Text(
                        "记录详情",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                    
                    Spacer(modifier = Modifier.height(8.dp))
                    
                    mergedRecord.records.forEach { recordItem ->
                        val timeFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                        
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                        ) {
                            Text(
                                text = timeFormat.format(recordItem.timestamp),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Medium,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                val locationText = buildString {
                                    if (recordItem.route.isNotEmpty() && recordItem.route != "<NUL>") {
                                        append(recordItem.route)
                                    }
                                    if (recordItem.position.isNotEmpty() && recordItem.position != "<NUL>") {
                                        if (isNotEmpty()) append(" ")
                                        append("${recordItem.position}K")
                                    }
                                }
                                
                                Text(
                                    text = locationText.ifEmpty { "位置未知" },
                                    fontSize = 11.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                
                                Row(
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    val directionText = when (recordItem.direction) {
                                        1 -> "下行"
                                        3 -> "上行"
                                        else -> "未知"
                                    }
                                    Text(
                                        text = directionText,
                                        fontSize = 11.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    
                                    val speedText = if (recordItem.speed.isNotEmpty() &&
                                                       recordItem.speed != "<NUL>" &&
                                                       !recordItem.speed.all { it == '*' || it == '-' }) {
                                        "${recordItem.speed}km/h"
                                    } else {
                                        "速度未知"
                                    }
                                    Text(
                                        text = speedText,
                                        fontSize = 11.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                    
                    val coordinates = mergedRecord.getAllCoordinates()
                    val recordsWithCoordinates = mergedRecord.records.filter { it.getCoordinates() != null }
                    
                    if (coordinates.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            "行进路径 (${coordinates.size}/${mergedRecord.records.size} 个记录有位置信息)",
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(220.dp)
                                .clip(RoundedCornerShape(8.dp)),
                            contentAlignment = Alignment.Center
                        ) {
                            AndroidView(
                                factory = { context ->
                                    MapView(context).apply {
                                        setTileSource(TileSourceFactory.MAPNIK)
                                        setMultiTouchControls(true)
                                        zoomController.setVisibility(org.osmdroid.views.CustomZoomButtonsController.Visibility.NEVER)
                                        
                                        try {
                                            val railwayTileSource = XYTileSource(
                                                "OpenRailwayMap", 8, 16, 256, ".png",
                                                arrayOf(
                                                    "https://a.tiles.openrailwaymap.org/standard/",
                                                    "https://b.tiles.openrailwaymap.org/standard/",
                                                    "https://c.tiles.openrailwaymap.org/standard/"
                                                ),
                                                "© OpenRailwayMap contributors, © OpenStreetMap contributors"
                                            )
                                            val railwayProvider = MapTileProviderBasic(context)
                                            railwayProvider.tileSource = railwayTileSource
                                            val railwayOverlay = TilesOverlay(railwayProvider, context)
                                            overlays.add(railwayOverlay)
                                        } catch (e: Exception) {
                                            e.printStackTrace()
                                        }
                                        
                                        if (coordinates.size > 1) {
                                            val polyline = Polyline().apply {
                                                setPoints(coordinates)
                                                outlinePaint.color = android.graphics.Color.BLUE
                                                outlinePaint.strokeWidth = 5f
                                            }
                                            overlays.add(polyline)
                                        }
                                        
                                        coordinates.forEachIndexed { index, coord ->
                                            val marker = Marker(this).apply {
                                                position = coord
                                                title = when (index) {
                                                    0 -> "起点"
                                                    coordinates.lastIndex -> "终点"
                                                    else -> "经过点 ${index + 1}"
                                                }
                                            }
                                            overlays.add(marker)
                                        }
                                        
                                        val centerLat = coordinates.map { it.latitude }.average()
                                        val centerLon = coordinates.map { it.longitude }.average()
                                        controller.setCenter(org.osmdroid.util.GeoPoint(centerLat, centerLon))
                                        controller.setZoom(12.0)
                                    }
                                },
                                update = { mapView ->
                                    mapView.invalidate()
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
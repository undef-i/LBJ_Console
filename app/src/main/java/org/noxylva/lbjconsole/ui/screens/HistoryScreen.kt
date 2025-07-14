package org.noxylva.lbjconsole.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ripple.rememberRipple
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.delay
import org.osmdroid.tileprovider.MapTileProviderBasic
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.tileprovider.tilesource.XYTileSource
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.mylocation.GpsMyLocationProvider
import org.osmdroid.views.overlay.mylocation.MyLocationNewOverlay
import org.osmdroid.views.overlay.TilesOverlay
import org.noxylva.lbjconsole.model.TrainRecord
import org.noxylva.lbjconsole.util.LocoInfoUtil
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun HistoryScreen(
    records: List<TrainRecord>,
    latestRecord: TrainRecord?,
    lastUpdateTime: Date?,
    temporaryStatusMessage: String? = null,
    locoInfoUtil: LocoInfoUtil? = null,
    onClearRecords: () -> Unit = {},
    onExportRecords: () -> Unit = {},
    onRecordClick: (TrainRecord) -> Unit = {},
    onClearLog: () -> Unit = {},
    onDeleteRecords: (List<TrainRecord>) -> Unit = {}
) {

    val refreshKey = latestRecord?.timestamp?.time ?: 0

    var isInEditMode by remember { mutableStateOf(false) }
    val selectedRecords = remember { mutableStateListOf<TrainRecord>() }

    val expandedStates = remember { mutableStateMapOf<String, Boolean>() }


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
    val filteredRecords = remember(records, refreshKey) {
        records
    }

    fun exitEditMode() {
        isInEditMode = false
        selectedRecords.clear()
    }

    LaunchedEffect(selectedRecords.size) {
        if (selectedRecords.isEmpty() && isInEditMode) {
            exitEditMode()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {

            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp)
                    .weight(1.0f)
            ) {
                if (filteredRecords.isEmpty()) {
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
                                    "上次接收数据: ${
                                        SimpleDateFormat(
                                            "HH:mm:ss",
                                            Locale.getDefault()
                                        ).format(lastUpdateTime)
                                    }",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.7f)
                                )
                            }
                        }
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(filteredRecords) { record ->
                            val isSelected = selectedRecords.contains(record)
                            val cardColor = when {
                                isSelected -> MaterialTheme.colorScheme.primaryContainer
                                else -> MaterialTheme.colorScheme.surface
                            }

                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                                colors = CardDefaults.cardColors(
                                    containerColor = cardColor
                                ),
                                shape = RoundedCornerShape(8.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .combinedClickable(
                                            onClick = {
                                                if (isInEditMode) {
                                                    if (isSelected) {
                                                        selectedRecords.remove(record)
                                                    } else {
                                                        selectedRecords.add(record)
                                                    }
                                                } else {
                                                    val id = record.timestamp.time.toString()
                                                    expandedStates[id] =
                                                        !(expandedStates[id] ?: false)
                                                    if (record == latestRecord) {
                                                        onRecordClick(record)
                                                    }
                                                }
                                            },
                                            onLongClick = {
                                                if (!isInEditMode) {
                                                    isInEditMode = true
                                                    selectedRecords.clear()
                                                    selectedRecords.add(record)
                                                }
                                            },
                                            interactionSource = remember { MutableInteractionSource() },
                                            indication = rememberRipple(bounded = true)
                                        )
                                ) {
                                    Column(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(16.dp)
                                    ) {
                                        val recordMap = record.toMap()

                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            val trainDisplay =
                                                recordMap["train"]?.toString() ?: "未知列车"

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

                                                if (formattedInfo.isNotEmpty() && formattedInfo != "<NUL>") {
                                                    Text(
                                                        text = formattedInfo,
                                                        fontSize = 14.sp,
                                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                                    )
                                                }
                                            }

                                            Text(
                                                text = "${record.rssi} dBm",
                                                fontSize = 10.sp,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }

                                        Spacer(modifier = Modifier.height(4.dp))

                                        if (recordMap.containsKey("time")) {
                                            recordMap["time"]?.split("\n")?.forEach { timeLine ->
                                                Text(
                                                    text = timeLine,
                                                    fontSize = 12.sp,
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
                                            val isValidRoute =
                                                routeStr.isNotEmpty() && !routeStr.all { it == '*' }

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
                                            val locoInfoText = locoInfoUtil.getLocoInfoDisplay(
                                                record.locoType,
                                                record.loco
                                            )
                                            if (locoInfoText != null) {
                                                Spacer(modifier = Modifier.height(4.dp))
                                                Text(
                                                    text = locoInfoText,
                                                    fontSize = 14.sp,
                                                    color = MaterialTheme.colorScheme.onSurface
                                                )
                                            }
                                        }

                                        val recordId = record.timestamp.time.toString()
                                        if (expandedStates[recordId] == true) {
                                            val coordinates = remember { record.getCoordinates() }

                                            if (coordinates != null) {
                                                Spacer(modifier = Modifier.height(8.dp))
                                            }

                                            if (coordinates != null) {

                                                Box(
                                                    modifier = Modifier
                                                        .fillMaxWidth()
                                                        .height(220.dp)
                                                        .padding(vertical = 4.dp)
                                                        .clip(RoundedCornerShape(8.dp)),
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    AndroidView(
                                                        modifier = Modifier.clickable(
                                                            indication = null,
                                                            interactionSource = remember { MutableInteractionSource() }
                                                        ) {},
                                                        factory = { context ->
                                                            MapView(context).apply {
                                                                setTileSource(TileSourceFactory.MAPNIK)
                                                                setMultiTouchControls(true)
                                                                zoomController.setVisibility(org.osmdroid.views.CustomZoomButtonsController.Visibility.NEVER)
                                                                isHorizontalMapRepetitionEnabled =
                                                                    false
                                                                isVerticalMapRepetitionEnabled =
                                                                    false
                                                                setHasTransientState(true)
                                                                setOnTouchListener { v, event ->
                                                                    v.parent?.requestDisallowInterceptTouchEvent(
                                                                        true
                                                                    )
                                                                    false
                                                                }
                                                                controller.setZoom(10.0)
                                                                controller.setCenter(coordinates)
                                                                this.isTilesScaledToDpi = true
                                                                this.setUseDataConnection(true)

                                                                try {
                                                                    val railwayTileSource =
                                                                        XYTileSource(
                                                                            "OpenRailwayMap",
                                                                            8, 16,
                                                                            256,
                                                                            ".png",
                                                                            arrayOf(
                                                                                "https://a.tiles.openrailwaymap.org/standard/",
                                                                                "https://b.tiles.openrailwaymap.org/standard/",
                                                                                "https://c.tiles.openrailwaymap.org/standard/"
                                                                            ),
                                                                            "© OpenRailwayMap contributors, © OpenStreetMap contributors"
                                                                        )

                                                                    val railwayProvider =
                                                                        MapTileProviderBasic(context)
                                                                    railwayProvider.tileSource =
                                                                        railwayTileSource

                                                                    val railwayOverlay =
                                                                        TilesOverlay(
                                                                            railwayProvider,
                                                                            context
                                                                        )
                                                                    railwayOverlay.loadingBackgroundColor =
                                                                        android.graphics.Color.TRANSPARENT
                                                                    railwayOverlay.loadingLineColor =
                                                                        android.graphics.Color.TRANSPARENT

                                                                    overlays.add(railwayOverlay)
                                                                } catch (e: Exception) {
                                                                    e.printStackTrace()
                                                                }


                                                                try {
                                                                    val locationProvider =
                                                                        GpsMyLocationProvider(
                                                                            context
                                                                        ).apply {
                                                                            locationUpdateMinDistance =
                                                                                10f
                                                                            locationUpdateMinTime =
                                                                                1000
                                                                        }

                                                                    MyLocationNewOverlay(
                                                                        locationProvider,
                                                                        this
                                                                    ).apply {
                                                                        enableMyLocation()

                                                                    }.also { overlays.add(it) }
                                                                } catch (e: Exception) {
                                                                    e.printStackTrace()
                                                                }

                                                                val marker = Marker(this)
                                                                marker.position = coordinates

                                                                val latStr = String.format(
                                                                    "%.4f",
                                                                    coordinates.latitude
                                                                )
                                                                val lonStr = String.format(
                                                                    "%.4f",
                                                                    coordinates.longitude
                                                                )
                                                                val coordStr =
                                                                    "${latStr}°N, ${lonStr}°E"
                                                                marker.title =
                                                                    recordMap["train"]?.toString()
                                                                        ?: "列车"

                                                                marker.snippet = coordStr

                                                                marker.setInfoWindowAnchor(
                                                                    Marker.ANCHOR_CENTER,
                                                                    0f
                                                                )

                                                                overlays.add(marker)
                                                                marker.showInfoWindow()
                                                            }
                                                        },
                                                        update = { mapView ->
                                                            mapView.invalidate()
                                                        }
                                                    )
                                                }
                                            }
                                            if (recordMap.containsKey("position_info")) {
                                                Spacer(modifier = Modifier.height(8.dp))
                                                Text(
                                                    text = recordMap["position_info"] ?: "",
                                                    fontSize = 14.sp,
                                                    color = MaterialTheme.colorScheme.onSurface
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
        }
    }
    
    if (isInEditMode) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.TopCenter
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .background(MaterialTheme.colorScheme.primary)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        IconButton(onClick = { exitEditMode() }) {
                            Icon(
                                imageVector = Icons.Default.Close,
                                contentDescription = "取消",
                                tint = MaterialTheme.colorScheme.onPrimary
                            )
                        }
                        Text(
                            "已选择 ${selectedRecords.size} 条记录",
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                    }

                    IconButton(
                        onClick = {
                            if (selectedRecords.isNotEmpty()) {
                                onDeleteRecords(selectedRecords.toList())
                                exitEditMode()
                            }
                        }
                    ) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = "删除所选记录",
                            tint = MaterialTheme.colorScheme.onPrimary
                        )
                    }
                }
            }
        }
    }
}
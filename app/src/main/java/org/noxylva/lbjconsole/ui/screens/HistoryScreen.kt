package org.noxylva.lbjconsole.ui.screens

import android.util.Log
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ripple.rememberRipple
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
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
import org.noxylva.lbjconsole.model.MergedTrainRecord
import org.noxylva.lbjconsole.model.MergeSettings
import org.noxylva.lbjconsole.model.GroupBy
import org.noxylva.lbjconsole.util.LocoInfoUtil
import org.noxylva.lbjconsole.util.TrainTypeUtil
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TrainRecordItem(
    record: TrainRecord,
    isSelected: Boolean,
    isInEditMode: Boolean,
    expandedStatesMap: MutableMap<String, Boolean>,
    latestRecord: TrainRecord?,
    locoInfoUtil: LocoInfoUtil?,
    trainTypeUtil: TrainTypeUtil?,
    onRecordClick: (TrainRecord) -> Unit,
    onToggleSelection: (TrainRecord) -> Unit,
    onLongClick: (TrainRecord) -> Unit,
    modifier: Modifier = Modifier
) {
    val recordId = record.uniqueId
    val isExpanded = expandedStatesMap[recordId] == true
    

    
    val cardColor = when {
        isSelected -> MaterialTheme.colorScheme.primaryContainer
        else -> MaterialTheme.colorScheme.surface
    }
    
    val cardScale = if (isSelected) 0.98f else 1f
    
    val cardElevation = if (isSelected) 6.dp else 2.dp

    Card(
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer {
                scaleX = cardScale
                scaleY = cardScale
            },
        elevation = CardDefaults.cardElevation(defaultElevation = cardElevation),
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
                            onToggleSelection(record)
                        } else {
                            val id = record.uniqueId
                            expandedStatesMap[id] = !(expandedStatesMap[id] ?: false)
                            if (record == latestRecord) {
                                onRecordClick(record)
                            }
                        }
                    },
                    onLongClick = { onLongClick(record) },
                    interactionSource = remember { MutableInteractionSource() },
                    indication = rememberRipple(bounded = true)
                )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                val recordId = record.uniqueId
                val isExpanded = expandedStatesMap[recordId] == true
                val recordMap = record.toMap(showDetailedTime = true)

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
                    
                    val trainType = if (record.train?.trim().isNullOrEmpty()) {
                        null
                    } else {
                        val lbjClassValue = record.lbjClass?.trim() ?: "NA"
                        trainTypeUtil?.getTrainType(lbjClassValue, record.train!!.trim())
                    }
                    if (!trainType.isNullOrEmpty()) {
                        Text(
                            text = trainType,
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
                Spacer(modifier = Modifier.height(8.dp))
                AnimatedVisibility(
                    visible = isExpanded,
                    enter = expandVertically(animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow)) + fadeIn(animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow)),
                    exit = shrinkVertically(animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow)) + fadeOut(animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow))
                ) {
                    Column {
                        val coordinates = remember { record.getCoordinates() }


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
                                            isHorizontalMapRepetitionEnabled = false
                                            isVerticalMapRepetitionEnabled = false
                                            setHasTransientState(true)
                                            setOnTouchListener { v, event ->
                                                v.parent?.requestDisallowInterceptTouchEvent(true)
                                                false
                                            }
                                            controller.setZoom(10.0)
                                            controller.setCenter(coordinates)
                                            this.isTilesScaledToDpi = true
                                            this.setUseDataConnection(true)

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
                                                railwayOverlay.loadingBackgroundColor = android.graphics.Color.TRANSPARENT
                                                railwayOverlay.loadingLineColor = android.graphics.Color.TRANSPARENT

                                                overlays.add(railwayOverlay)
                                            } catch (e: Exception) {
                                                e.printStackTrace()
                                            }

                                            try {
                                                val locationProvider = GpsMyLocationProvider(context).apply {
                                                    locationUpdateMinDistance = 10f
                                                    locationUpdateMinTime = 1000
                                                }

                                                MyLocationNewOverlay(locationProvider, this).apply {
                                                    enableMyLocation()
                                                }.also { overlays.add(it) }
                                            } catch (e: Exception) {
                                                e.printStackTrace()
                                            }

                                            val marker = Marker(this)
                                            marker.position = coordinates

                                            val latStr = String.format("%.4f", coordinates.latitude)
                                            val lonStr = String.format("%.4f", coordinates.longitude)
                                            val coordStr = "${latStr}°N, ${lonStr}°E"
                                            marker.title = recordMap["train"]?.toString() ?: "列车"
                                            marker.snippet = coordStr
                                            marker.setInfoWindowAnchor(Marker.ANCHOR_CENTER, 0f)

                                            overlays.add(marker)
                                            marker.showInfoWindow()
                                        }
                                    },
                                    update = { mapView -> mapView.invalidate() }
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

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MergedTrainRecordItem(
    mergedRecord: MergedTrainRecord,
    expandedStatesMap: MutableMap<String, Boolean>,
    locoInfoUtil: LocoInfoUtil?,
    trainTypeUtil: TrainTypeUtil?,
    mergeSettings: MergeSettings? = null,
    isInEditMode: Boolean = false,
    selectedRecords: List<TrainRecord> = emptyList(),
    onToggleSelection: (TrainRecord) -> Unit = {},
    onLongClick: (TrainRecord) -> Unit = {},
    modifier: Modifier = Modifier
) {
    val recordId = mergedRecord.groupKey
    val isExpanded = expandedStatesMap[recordId] == true
    val latestRecord = mergedRecord.latestRecord
    
    val hasSelectedRecords = mergedRecord.records.any { selectedRecords.contains(it) }
    
    val cardColor = when {
        hasSelectedRecords -> MaterialTheme.colorScheme.primaryContainer
        else -> MaterialTheme.colorScheme.surface
    }
    
    val cardScale = if (hasSelectedRecords) 0.98f else 1f
    
    val cardElevation = if (hasSelectedRecords) 6.dp else 2.dp

    Card(
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer {
                scaleX = cardScale
                scaleY = cardScale
            },
        elevation = CardDefaults.cardElevation(defaultElevation = cardElevation),
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
                            if (hasSelectedRecords) {
                                mergedRecord.records.forEach { record ->
                                    if (selectedRecords.contains(record)) {
                                        onToggleSelection(record)
                                    }
                                }
                            } else {
                                mergedRecord.records.forEach { record ->
                                    if (!selectedRecords.contains(record)) {
                                        onToggleSelection(record)
                                    }
                                }
                            }
                        } else {
                            expandedStatesMap[recordId] = !isExpanded
                        }
                    },
                    onLongClick = {
                        if (!isInEditMode) {
                            onLongClick(mergedRecord.records.first())
                        }
                    },
                    interactionSource = remember { MutableInteractionSource() },
                    indication = rememberRipple(bounded = true)
                )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                val recordMap = latestRecord.toMap(showDetailedTime = true)
                
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
                    
                    val trainType = if (latestRecord.train?.trim().isNullOrEmpty()) {
                        null
                    } else {
                        val lbjClassValue = latestRecord.lbjClass?.trim() ?: "NA"
                        trainTypeUtil?.getTrainType(lbjClassValue, latestRecord.train!!.trim())
                    }
                    if (!trainType.isNullOrEmpty()) {
                        Text(
                            text = trainType,
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

                        val directionText = when (latestRecord.direction) {
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
                        latestRecord.locoType.isNotEmpty() && latestRecord.loco.isNotEmpty() -> {
                            val shortLoco = if (latestRecord.loco.length > 5) {
                                latestRecord.loco.takeLast(5)
                            } else {
                                latestRecord.loco
                            }
                            "${latestRecord.locoType}-${shortLoco}"
                        }
                        latestRecord.locoType.isNotEmpty() -> latestRecord.locoType
                        latestRecord.loco.isNotEmpty() -> latestRecord.loco
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
                    val routeStr = latestRecord.route.trim()
                    val isValidRoute = routeStr.isNotEmpty() && !routeStr.all { it == '*' }

                    val position = latestRecord.position.trim()
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

                    val speed = latestRecord.speed.trim()
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

                if (locoInfoUtil != null && latestRecord.locoType.isNotEmpty() && latestRecord.loco.isNotEmpty()) {
                    val locoInfoText = locoInfoUtil.getLocoInfoDisplay(
                        latestRecord.locoType,
                        latestRecord.loco
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
                Spacer(modifier = Modifier.height(8.dp))
                AnimatedVisibility(
                    visible = isExpanded,
                    enter = expandVertically(animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow)) + fadeIn(animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow)),
                    exit = shrinkVertically(animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow)) + fadeOut(animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow))
                ) {
                    Column {
                        val coordinates = remember { latestRecord.getCoordinates() }



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
                                        isHorizontalMapRepetitionEnabled = false
                                        isVerticalMapRepetitionEnabled = false
                                        setHasTransientState(true)
                                        setOnTouchListener { v, event ->
                                            v.parent?.requestDisallowInterceptTouchEvent(true)
                                            false
                                        }
                                        controller.setZoom(10.0)
                                        controller.setCenter(coordinates)
                                        this.isTilesScaledToDpi = true
                                        this.setUseDataConnection(true)

                                        try {
                                            val railwayTileSource = XYTileSource(
                                                "OpenRailwayMap", 8, 16, 256, ".png",
                                                arrayOf(
                                                    "https://a.tiles.openrailwayMap.org/standard/",
                                                    "https://b.tiles.openrailwaymap.org/standard/",
                                                    "https://c.tiles.openrailwaymap.org/standard/"
                                                ),
                                                "© OpenRailwayMap contributors, © OpenStreetMap contributors"
                                            )

                                            val railwayProvider = MapTileProviderBasic(context)
                                            railwayProvider.tileSource = railwayTileSource

                                            val railwayOverlay = TilesOverlay(railwayProvider, context)
                                            railwayOverlay.loadingBackgroundColor = android.graphics.Color.TRANSPARENT
                                            railwayOverlay.loadingLineColor = android.graphics.Color.TRANSPARENT

                                            overlays.add(railwayOverlay)
                                        } catch (e: Exception) {
                                            e.printStackTrace()
                                        }

                                        try {
                                            val locationProvider = GpsMyLocationProvider(context).apply {
                                                locationUpdateMinDistance = 10f
                                                locationUpdateMinTime = 1000
                                            }

                                            MyLocationNewOverlay(locationProvider, this).apply {
                                                enableMyLocation()
                                            }.also { overlays.add(it) }
                                        } catch (e: Exception) {
                                            e.printStackTrace()
                                        }

                                        val marker = Marker(this)
                                        marker.position = coordinates

                                        val latStr = String.format("%.4f", coordinates.latitude)
                                        val lonStr = String.format("%.4f", coordinates.longitude)
                                        val coordStr = "${latStr}°N, ${lonStr}°E"
                                        marker.title = recordMap["train"]?.toString() ?: "列车"
                                        marker.snippet = coordStr
                                        marker.setInfoWindowAnchor(Marker.ANCHOR_CENTER, 0f)

                                        overlays.add(marker)
                                        marker.showInfoWindow()
                                    }
                                },
                                update = { mapView -> mapView.invalidate() }
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
                        
                        Spacer(modifier = Modifier.height(8.dp))
                        HorizontalDivider()
                        Spacer(modifier = Modifier.height(8.dp))
                        
                        mergedRecord.records.filter { it != mergedRecord.latestRecord }.forEach { recordItem ->
                        val timeFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                        
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = timeFormat.format(recordItem.timestamp),
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                                
                                val extraInfo = when (mergeSettings?.groupBy) {
                                    GroupBy.LOCO_ONLY -> {
                                        if (recordItem.train.isNotEmpty() && recordItem.train != "<NUL>") {
                                            recordItem.train
                                        } else null
                                    }
                                    GroupBy.TRAIN_ONLY -> {
                                        if (recordItem.loco.isNotEmpty() && recordItem.loco != "<NUL>") {
                                            "${recordItem.locoType}-${recordItem.loco}"
                                        } else null
                                    }
                                    GroupBy.TRAIN_OR_LOCO -> {
                                        val latestTrain = mergedRecord.latestRecord.train.trim()
                                        val latestLoco = mergedRecord.latestRecord.loco.trim()
                                        val recordTrain = recordItem.train.trim()
                                        val recordLoco = recordItem.loco.trim()
                                        
                                        when {
                                            latestTrain.isNotEmpty() && latestTrain != "<NUL>" && 
                                            recordTrain.isNotEmpty() && recordTrain != "<NUL>" && 
                                            latestTrain == recordTrain && latestLoco != recordLoco -> {
                                                if (recordLoco.isNotEmpty() && recordLoco != "<NUL>") {
                                                    "${recordItem.locoType}-${recordLoco}"
                                                } else null
                                            }
                                            latestLoco.isNotEmpty() && latestLoco != "<NUL>" && 
                                            recordLoco.isNotEmpty() && recordLoco != "<NUL>" && 
                                            latestLoco == recordLoco && latestTrain != recordTrain -> {
                                                if (recordTrain.isNotEmpty() && recordTrain != "<NUL>") {
                                                    recordTrain
                                                } else null
                                            }
                                            else -> null
                                        }
                                    }
                                    else -> null
                                }
                                
                                if (extraInfo != null) {
                                    Text(
                                        text = extraInfo,
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                            
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
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun HistoryScreen(
    records: List<Any>,
    latestRecord: TrainRecord?,
    lastUpdateTime: Date?,
    temporaryStatusMessage: String? = null,
    locoInfoUtil: LocoInfoUtil? = null,
    trainTypeUtil: TrainTypeUtil? = null,
    mergeSettings: MergeSettings? = null,
    onClearRecords: () -> Unit = {},
    onRecordClick: (TrainRecord) -> Unit = {},
    onClearLog: () -> Unit = {},
    onDeleteRecords: (List<TrainRecord>) -> Unit = {},
    editMode: Boolean = false,
    selectedRecords: Set<String> = emptySet(),
    expandedStates: Map<String, Boolean> = emptyMap(),
    scrollPosition: Int = 0,
    scrollOffset: Int = 0,
    onStateChange: (Boolean, Set<String>, Map<String, Boolean>, Int, Int) -> Unit = { _, _, _, _, _ -> }
) {

    val refreshKey = latestRecord?.timestamp?.time ?: 0
    var wasAtTopBeforeUpdate by remember { mutableStateOf(false) }

    var isInEditMode by remember(editMode) { mutableStateOf(editMode) }
    val selectedRecordsList = remember(selectedRecords) { 
        mutableStateListOf<TrainRecord>().apply {
            records.forEach { item ->
                when (item) {
                    is TrainRecord -> {
                        if (selectedRecords.contains(item.uniqueId)) {
                            add(item)
                        }
                    }
                    is MergedTrainRecord -> {
                        item.records.forEach { record ->
                            if (selectedRecords.contains(record.uniqueId)) {
                                add(record)
                            }
                        }
                    }
                }
            }
        }
    }
    val expandedStatesMap = remember(expandedStates) { 
        mutableStateMapOf<String, Boolean>().apply { putAll(expandedStates) }
    }
    
    val listState = rememberLazyListState(
        initialFirstVisibleItemIndex = scrollPosition,
        initialFirstVisibleItemScrollOffset = scrollOffset
    )


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
        }
    }
    val filteredRecords = remember(records, refreshKey) {
        records
    }


    LaunchedEffect(isInEditMode, selectedRecordsList.size) {
        val selectedIds = selectedRecordsList.map { it.uniqueId }.toSet()
        onStateChange(isInEditMode, selectedIds, expandedStatesMap.toMap(), listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset)
    }
    
    LaunchedEffect(expandedStatesMap.toMap()) {
        if (!isInEditMode) {
            val selectedIds = selectedRecordsList.map { it.uniqueId }.toSet()
            delay(50)
            onStateChange(isInEditMode, selectedIds, expandedStatesMap.toMap(), listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset)
        }
    }
    
    LaunchedEffect(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset) {
        if (!isInEditMode) {
            val selectedIds = selectedRecordsList.map { it.uniqueId }.toSet()
            onStateChange(isInEditMode, selectedIds, expandedStatesMap.toMap(), listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset)
        }
    }

    LaunchedEffect(selectedRecordsList.size) {
        if (selectedRecordsList.isEmpty() && isInEditMode) {
            isInEditMode = false
            onStateChange(false, emptySet(), expandedStatesMap.toMap(), listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset)
        }
    }
    
    LaunchedEffect(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset) {
        if (!isInEditMode && filteredRecords.isNotEmpty()) {
            wasAtTopBeforeUpdate = listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset <= 100
        }
    }

    LaunchedEffect(refreshKey) {
        if (refreshKey > 0 && !isInEditMode && filteredRecords.isNotEmpty() && wasAtTopBeforeUpdate) {
            try {
                listState.animateScrollToItem(0, 0)
            } catch (e: Exception) {
                listState.scrollToItem(0, 0)
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
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
                        state = listState,
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp)
                    ) {
                        itemsIndexed(filteredRecords, key = { _, item -> 
                            when (item) {
                                is TrainRecord -> item.uniqueId
                                is MergedTrainRecord -> item.groupKey
                                else -> item.hashCode()
                            }
                        }) { index, item ->
                            when (item) {
                                is TrainRecord -> {
                                    TrainRecordItem(
                                        modifier = Modifier,
                                        record = item,
                                        isSelected = selectedRecordsList.contains(item),
                                        isInEditMode = isInEditMode,
                                        expandedStatesMap = expandedStatesMap,
                                        latestRecord = latestRecord,
                                        locoInfoUtil = locoInfoUtil,
                                        trainTypeUtil = trainTypeUtil,
                                        onRecordClick = onRecordClick,
                                        onToggleSelection = { record ->
                                            if (selectedRecordsList.contains(record)) {
                                                selectedRecordsList.remove(record)
                                            } else {
                                                selectedRecordsList.add(record)
                                            }
                                        },
                                        onLongClick = { record ->
                                            if (!isInEditMode) {
                                                isInEditMode = true
                                                selectedRecordsList.clear()
                                                selectedRecordsList.add(record)
                                            }
                                        }
                                    )
                                }
                                is MergedTrainRecord -> {
                                    MergedTrainRecordItem(
                                        modifier = Modifier,
                                        mergedRecord = item,
                                        expandedStatesMap = expandedStatesMap,
                                        locoInfoUtil = locoInfoUtil,
                                        trainTypeUtil = trainTypeUtil,
                                        mergeSettings = mergeSettings,
                                        isInEditMode = isInEditMode,
                                        selectedRecords = selectedRecordsList,
                                        onToggleSelection = { record ->
                                            if (selectedRecordsList.contains(record)) {
                                                selectedRecordsList.remove(record)
                                            } else {
                                                selectedRecordsList.add(record)
                                            }
                                        },
                                        onLongClick = { record ->
                                            if (!isInEditMode) {
                                                isInEditMode = true
                                                selectedRecordsList.clear()
                                                selectedRecordsList.add(record)
                                            }
                                        }
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
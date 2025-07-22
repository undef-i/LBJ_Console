package org.noxylva.lbjconsole.ui.screens

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.util.Log
import android.view.ViewGroup
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.launch
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.MapTileProviderBasic
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.tileprovider.tilesource.XYTileSource
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.*
import org.osmdroid.views.overlay.mylocation.GpsMyLocationProvider
import org.osmdroid.views.overlay.mylocation.MyLocationNewOverlay
import org.osmdroid.events.MapListener
import org.osmdroid.events.ScrollEvent
import org.osmdroid.events.ZoomEvent
import org.noxylva.lbjconsole.model.TrainRecord
import java.io.File


@Composable
fun MapScreen(
    records: List<TrainRecord>,
    onCenterMap: () -> Unit = {},
    onLocationError: (String) -> Unit = {},
    centerPosition: Pair<Double, Double>? = null,
    zoomLevel: Double = 10.0,
    railwayLayerVisible: Boolean = true,
    onStateChange: (Pair<Double, Double>?, Double, Boolean) -> Unit = { _, _, _ -> }
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val coroutineScope = rememberCoroutineScope()
    
    
    LaunchedEffect(Unit) {
        try {
            
            val osmCacheDir = File(context.cacheDir, "osm").apply { mkdirs() }
            val tileCache = File(osmCacheDir, "tiles").apply { mkdirs() }

            
            Configuration.getInstance().apply {
                userAgentValue = context.packageName
                load(context, context.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
                osmdroidBasePath = osmCacheDir
                osmdroidTileCache = tileCache
                expirationOverrideDuration = 86400000L
                gpsWaitTime = 0L
                tileDownloadThreads = 6
                tileFileSystemThreads = 6
                tileFileSystemCacheTrimBytes = 1024L * 1024L * 2000
                tileFileSystemCacheMaxBytes = 1024L * 1024L * 500L
            }
        } catch (e: Exception) {
            e.printStackTrace()
            onLocationError("Map initialization failed: ${e.localizedMessage}")
        }
    }
    
    
    val validRecords = records.filter { it.getCoordinates() != null }
    
    val defaultPosition = GeoPoint(39.0851, 117.2015)
    
    var isMapInitialized by remember { mutableStateOf(false) }
    val mapViewRef = remember { mutableStateOf<MapView?>(null) }
    
    
    
    val railwayOverlayRef = remember { mutableStateOf<TilesOverlay?>(null) }
    val myLocationOverlayRef = remember { mutableStateOf<MyLocationNewOverlay?>(null) }
    var currentLocation by remember { mutableStateOf<GeoPoint?>(null) }
    var showDetailDialog by remember { mutableStateOf(false) }
    var selectedRecord by remember { mutableStateOf<TrainRecord?>(null) }
    var dialogPosition by remember { mutableStateOf<GeoPoint?>(null) }
    
    var railwayLayerVisibleState by remember(railwayLayerVisible) { mutableStateOf(railwayLayerVisible) }
    
    fun updateMarkers() {
        val mapView = mapViewRef.value ?: return
        
        mapView.overlays.removeAll { it is Marker }
        
        validRecords.forEach { record ->
            record.getCoordinates()?.let { point ->
                val marker = Marker(mapView).apply {
                    position = point
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                    
                    val recordMap = record.toMap()
                    title = recordMap["train"]?.toString() ?: "列车"
                    
                    val latStr = String.format("%.4f", point.latitude)
                    val lonStr = String.format("%.4f", point.longitude)
                    val coordStr = "${latStr}°N, ${lonStr}°E"
                    snippet = coordStr
                    
                    setInfoWindowAnchor(Marker.ANCHOR_CENTER, 0f)
                    
                    setOnMarkerClickListener { clickedMarker, _ ->
                        selectedRecord = record
                        dialogPosition = point
                        showDetailDialog = true
                        true
                    }
                }
                
                mapView.overlays.add(marker)
                marker.showInfoWindow()
            }
        }
        
        mapView.invalidate()
    }
    
    LaunchedEffect(records) {
        if (isMapInitialized) {
            updateMarkers()
        }
    }
    
    
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            try {
                when (event) {
                    Lifecycle.Event.ON_RESUME -> {
                        mapViewRef.value?.onResume()
                        myLocationOverlayRef.value?.enableMyLocation()
                    }
                    Lifecycle.Event.ON_PAUSE -> {
                        mapViewRef.value?.onPause()
                        myLocationOverlayRef.value?.disableMyLocation()
                    }
                    Lifecycle.Event.ON_DESTROY -> {
                        mapViewRef.value?.onDetach()
                    }
                    else -> {}
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        
        lifecycleOwner.lifecycle.addObserver(observer)
        
        onDispose {
            try {
                lifecycleOwner.lifecycle.removeObserver(observer)
                myLocationOverlayRef.value?.disableMyLocation()
                mapViewRef.value?.onDetach()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
    

    
    
    fun updateRailwayLayerVisibility(visible: Boolean) {
        railwayOverlayRef.value?.let { overlay ->
            overlay.isEnabled = visible
            
            if (!visible) {
                
                val transparentFilter = PorterDuffColorFilter(
                    Color.argb(0, 255, 255, 255),
                    PorterDuff.Mode.SRC_IN
                )
                overlay.setColorFilter(transparentFilter)
            } else {
                
                overlay.setColorFilter(null)
            }
            mapViewRef.value?.invalidate()
            Log.d("MapScreen", "OpenRailwayMap layer ${if (visible) "shown" else "hidden"}")
        }
    }
    
    Box(modifier = Modifier.fillMaxSize()) {
        
        AndroidView(
            factory = { ctx ->
                try {
                    MapView(ctx).apply {
                        layoutParams = ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                        
                        setTileSource(TileSourceFactory.MAPNIK)
                        setMultiTouchControls(true)
                        zoomController.setVisibility(org.osmdroid.views.CustomZoomButtonsController.Visibility.NEVER)
                        isTilesScaledToDpi = true
                        tilesScaleFactor = ctx.resources.displayMetrics.density * 0.2f
                        setHorizontalMapRepetitionEnabled(false)
                        setVerticalMapRepetitionEnabled(false)
                        isHorizontalMapRepetitionEnabled = false
                        isVerticalMapRepetitionEnabled = false
                        setUseDataConnection(true)
                        minZoomLevel = 4.0
                        maxZoomLevel = 18.0
                        
                        
                        
                        
                        try {
                            val provider = MapTileProviderBasic(ctx)
                            provider.tileSource = TileSourceFactory.MAPNIK
                            val tileOverlay = TilesOverlay(provider, ctx)
                            tileOverlay.loadingBackgroundColor = Color.TRANSPARENT
                            tileOverlay.loadingLineColor = Color.TRANSPARENT
                            overlays.add(tileOverlay)
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                        
                        
                        try {
                            

                            val railwayTileSource = XYTileSource(
                                "OpenRailwayMap",
                                0, 24,
                                256,
                                ".png",
                                arrayOf(
                                    "https://a.tiles.openrailwaymap.org/standard/",
                                    "https://b.tiles.openrailwaymap.org/standard/",
                                    "https://c.tiles.openrailwaymap.org/standard/"
                                ),
                                "© OpenRailwayMap contributors, © OpenStreetMap contributors"
                            )
                            
                            
                            val railwayProvider = MapTileProviderBasic(ctx)
                            railwayProvider.tileSource = railwayTileSource
                            
                            
                            val railwayOverlay = TilesOverlay(railwayProvider, ctx)
                            
                            
                            val railwayColorFilter = PorterDuffColorFilter(
                                Color.rgb(0, 51, 153),
                                PorterDuff.Mode.MULTIPLY
                            )
                            railwayOverlay.setColorFilter(railwayColorFilter)
                            railwayOverlay.loadingBackgroundColor = Color.TRANSPARENT
                            railwayOverlay.loadingLineColor = Color.TRANSPARENT
                            
                            
                            overlays.add(railwayOverlay)
                            
                            railwayOverlayRef.value = railwayOverlay
                            
                            Log.d("MapScreen", "OpenRailwayMap layer loaded")
                        } catch (e: Exception) {
                            e.printStackTrace()
                            Log.e("MapScreen", "Failed to load OpenRailwayMap layer: ${e.message}")
                        }
                        
                        
                        centerPosition?.let { (lat, lon) ->
                            controller.setCenter(GeoPoint(lat, lon))
                            controller.setZoom(zoomLevel)
                            isMapInitialized = true
                            Log.d("MapScreen", "Map initialized with saved state: lat=$lat, lon=$lon, zoom=$zoomLevel")
                        } ?: run {
                            if (validRecords.isNotEmpty()) {
                                validRecords.lastOrNull()?.getCoordinates()?.let { lastPoint ->
                                    controller.setCenter(lastPoint)
                                    controller.setZoom(12.0)
                                }
                            } else {
                                controller.setCenter(defaultPosition)
                                controller.setZoom(10.0)
                            }
                        }
                        
                        
                        try {
                            
                            val locationProvider = GpsMyLocationProvider(ctx).apply {
                                locationUpdateMinDistance = 10f 
                                locationUpdateMinTime = 5000 
                            }
                            
                            
                            val myLocationOverlay = MyLocationNewOverlay(locationProvider, this).apply {
                                enableMyLocation()
                                
                                runOnFirstFix {
                                    try {
                                        myLocation?.let { location ->
                                            currentLocation = GeoPoint(location.latitude, location.longitude)
                                            
                                            if (!isMapInitialized && centerPosition == null) {
                                                controller.setCenter(location)
                                                controller.setZoom(15.0)
                                                isMapInitialized = true
                                                Log.d("MapScreen", "Map initialized with GPS position: $location")
                                            }
                                        } ?: run {
                                            if (!isMapInitialized && centerPosition == null) {
                                                if (validRecords.isNotEmpty()) {
                                                    validRecords.lastOrNull()?.getCoordinates()?.let { lastPoint ->
                                                        controller.setCenter(lastPoint)
                                                        controller.setZoom(12.0)
                                                        isMapInitialized = true
                                                        Log.d("MapScreen", "Map initialized with last record position: $lastPoint")
                                                    }
                                                } else {
                                                    controller.setCenter(defaultPosition)
                                                    isMapInitialized = true
                                                }
                                            }
                                        }
                                    } catch (e: Exception) {
                                        e.printStackTrace()
                                        if (!isMapInitialized && centerPosition == null) {
                                            if (validRecords.isNotEmpty()) {
                                                validRecords.lastOrNull()?.getCoordinates()?.let { lastPoint ->
                                                    controller.setCenter(lastPoint)
                                                    controller.setZoom(12.0)
                                                    isMapInitialized = true
                                                    Log.d("MapScreen", "Map fallback to last record position: $lastPoint")
                                                }
                                            } else {
                                                controller.setCenter(defaultPosition)
                                                isMapInitialized = true
                                            }
                                        }
                                    }
                                }
                            }
                            overlays.add(myLocationOverlay)
                            myLocationOverlayRef.value = myLocationOverlay
                            
                            
                            
                            
                            ScaleBarOverlay(this).apply {
                                setCentred(false)
                                setScaleBarOffset(5, ctx.resources.displayMetrics.heightPixels - 50)
                                setTextSize(12.0f * ctx.resources.displayMetrics.density / 2)
                                setEnableAdjustLength(true)
                                setAlignBottom(true)
                                setLineWidth(2.0f)
                            }.also { overlays.add(it) }
                            
                            
                            addMapListener(object : MapListener {
                                override fun onScroll(event: ScrollEvent?): Boolean {
                                    val center = mapCenter
                                    val zoom = zoomLevelDouble
                                    onStateChange(
                                        center.latitude to center.longitude,
                                        zoom,
                                        railwayLayerVisibleState
                                    )
                                    return true
                                }
                                
                                override fun onZoom(event: ZoomEvent?): Boolean {
                                    val center = mapCenter
                                    val zoom = zoomLevelDouble
                                    onStateChange(
                                        center.latitude to center.longitude,
                                        zoom,
                                        railwayLayerVisibleState
                                    )
                                    return true
                                }
                            })
                        } catch (e: Exception) {
                            e.printStackTrace()
                            onLocationError("Map component initialization failed: ${e.localizedMessage}")
                        }
                        
                        mapViewRef.value = this
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                    onLocationError("Map creation failed: ${e.localizedMessage}")
                    
                    MapView(ctx).apply {
                        layoutParams = ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                    }
                }
            },
            modifier = Modifier.fillMaxSize(),
            update = { mapView ->
                
                coroutineScope.launch {
                    updateMarkers()
                    updateRailwayLayerVisibility(railwayLayerVisibleState)
                }
            }
        )
        
        
        if (!isMapInitialized) {
            CircularProgressIndicator(
                modifier = Modifier
                    .size(24.dp)
                    .align(Alignment.Center),
                strokeWidth = 2.dp
            )
        }
        
        
        Column(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            
            
            
            FloatingActionButton(
                onClick = {
                    myLocationOverlayRef.value?.let { overlay ->
                        overlay.enableFollowLocation()
                        overlay.enableMyLocation()
                        overlay.myLocation?.let { location ->
                            mapViewRef.value?.controller?.setCenter(location)
                        }
                    }
                },
                modifier = Modifier.size(40.dp),
                containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.9f),
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer
            ) {
                Icon(
                    imageVector = Icons.Filled.MyLocation,
                    contentDescription = "定位",
                    modifier = Modifier.size(20.dp)
                )
            }
            
            
            FloatingActionButton(
                onClick = {
                    railwayLayerVisibleState = !railwayLayerVisibleState
                    updateRailwayLayerVisibility(railwayLayerVisibleState)
                    
                    
                    mapViewRef.value?.let { mapView ->
                        val center = mapView.mapCenter
                        val zoom = mapView.zoomLevelDouble
                        onStateChange(
                            center.latitude to center.longitude,
                            zoom,
                            railwayLayerVisibleState
                        )
                    }
                },
                modifier = Modifier.size(40.dp),
                containerColor = if (railwayLayerVisibleState)
                    MaterialTheme.colorScheme.primary.copy(alpha = 0.9f)
                else
                    MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.9f),
                contentColor = if (railwayLayerVisibleState)
                    MaterialTheme.colorScheme.onPrimary 
                else
                    MaterialTheme.colorScheme.onPrimaryContainer
            ) {
                Icon(
                    imageVector = Icons.Filled.Layers,
                    contentDescription = "铁路图层",
                    modifier = Modifier.size(20.dp)
                )
            }
            
            
            FloatingActionButton(
                onClick = {
                    mapViewRef.value?.let { mapView ->
                        myLocationOverlayRef.value?.myLocation?.let { gpsLocation ->
                            mapView.controller.setCenter(gpsLocation)
                            mapView.controller.setZoom(15.0)
                            Log.d("MapScreen", "Refresh button: GPS position used")
                        } ?: run {
                            if (validRecords.isNotEmpty()) {
                                validRecords.lastOrNull()?.getCoordinates()?.let { point ->
                                    mapView.controller.setCenter(point)
                                    mapView.controller.setZoom(12.0)
                                    Log.d("MapScreen", "Refresh button: last record position used")
                                }
                            } else {
                                mapView.controller.setCenter(defaultPosition)
                                mapView.controller.setZoom(10.0)
                                Log.d("MapScreen", "Refresh button: default position used")
                            }
                        }
                    }
                    onCenterMap()
                },
                modifier = Modifier.size(40.dp),
                containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.9f),
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer
            ) {
                Icon(
                    imageVector = Icons.Filled.Refresh,
                    contentDescription = "居中地图",
                    modifier = Modifier.size(20.dp)
                )
            }
        }
        
        
        Surface(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(8.dp)
                .height(32.dp),
            color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.9f),
            shape = MaterialTheme.shapes.small
        ) {
            Text(
                text = "${validRecords.size}条记录",
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
        }

        
        if (showDetailDialog && selectedRecord != null) {
            TrainMarkerDialog(
                record = selectedRecord!!,
                position = dialogPosition,
                onDismiss = { showDetailDialog = false }
            )
        }
    }
}


fun Context.getCompactMarkerDrawable(color: Int): Drawable {
    
    val drawable = this.resources.getDrawable(android.R.drawable.ic_menu_mylocation, this.theme)
    drawable.setTint(color)
    return drawable
}


private fun Int.directionText(): String = when (this) {
    1 -> "↓"
    3 -> "↑"
    else -> "?"
}

@Composable
private fun TrainMarkerDialog(
    record: TrainRecord,
    position: GeoPoint?,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            
            val recordMap = record.toMap()
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(text = recordMap["train"]?.toString() ?: "列车", style = MaterialTheme.typography.titleLarge)
                recordMap["direction"]?.let { direction ->
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = direction,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        },
        text = {
            Column {
                
                record.toMap().forEach { (key, value) ->
                    if (key != "train" && key != "direction") {
                        Text(
                            text = value,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(vertical = 2.dp)
                        )
                    }
                }
                
                
                position?.let {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "坐标: ${String.format("%.6f", it.latitude)}, ${String.format("%.6f", it.longitude)}",
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("确定")
            }
        }
    )
}
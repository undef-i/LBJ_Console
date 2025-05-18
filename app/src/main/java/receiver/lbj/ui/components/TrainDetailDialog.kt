package receiver.lbj.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import receiver.lbj.model.TrainRecord

@Composable
fun TrainDetailDialog(
    trainRecord: TrainRecord,
    onDismiss: () -> Unit
) {
    val recordMap = trainRecord.toMap()
    val coordinates = remember { trainRecord.getCoordinates() }
    
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            dismissOnBackPress = true,
            dismissOnClickOutside = true
        )
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 8.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                
                Text(
                    text = "列车详情",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(bottom = 16.dp)
                )
                
                
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    DetailItem("列车号", recordMap["train"] ?: "--")
                    DetailItem("方向", recordMap["direction"] ?: "未知")
                }
                
                Divider(modifier = Modifier.padding(vertical = 8.dp))
                
                
                DetailItem("接收时间", recordMap["timestamp"] ?: "--")
                DetailItem("列车时间", recordMap["time"] ?: "--")
                
                Divider(modifier = Modifier.padding(vertical = 8.dp))
                
                
                DetailItem("速度", recordMap["speed"] ?: "--")
                DetailItem("位置", recordMap["position"] ?: "--")
                DetailItem("位置信息", recordMap["position_info"] ?: "--")
                
                Divider(modifier = Modifier.padding(vertical = 8.dp))
                
                
                DetailItem("机车号", recordMap["loco"] ?: "--")
                DetailItem("机车类型", recordMap["loco_type"] ?: "--")
                DetailItem("列车类型", recordMap["lbj_class"] ?: "--")
                
                Divider(modifier = Modifier.padding(vertical = 8.dp))
                
                
                DetailItem("路线", recordMap["route"] ?: "--")
                DetailItem("信号强度", recordMap["rssi"] ?: "--")
                
                if (coordinates != null) {
                    Divider(modifier = Modifier.padding(vertical = 8.dp))
                    
                    DetailItem(
                        label = "经纬度",
                        value = "纬度: ${coordinates.latitude}, 经度: ${coordinates.longitude}"
                    )
                    
                    
                    Spacer(modifier = Modifier.height(8.dp))
                    
                    
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp)
                            .padding(vertical = 8.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        AndroidView(
                            factory = { context ->
                                MapView(context).apply {
                                    setTileSource(TileSourceFactory.MAPNIK)
                                    setMultiTouchControls(true)
                                    controller.setZoom(15.0)
                                    controller.setCenter(coordinates)
                                    
                                    
                                    val marker = Marker(this)
                                    marker.position = coordinates
                                    marker.setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                                    marker.title = recordMap["train"] ?: "列车"
                                    overlays.add(marker)
                                }
                            },
                            update = { mapView ->
                                mapView.controller.setCenter(coordinates)
                                mapView.invalidate()
                            }
                        )
                    }
                }
                
                Spacer(modifier = Modifier.height(16.dp))
                
                
                Button(
                    onClick = onDismiss,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp)
                ) {
                    Text("关闭")
                }
            }
        }
    }
}

@Composable
private fun DetailItem(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge
        )
    }
}
package org.noxylva.lbjconsole.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.HorizontalDivider
import org.noxylva.lbjconsole.model.TrainRecord

@Composable
fun TrainInfoCard(
    trainRecord: TrainRecord,
    modifier: Modifier = Modifier
) {
    val recordMap = trainRecord.toMap()
    
    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp, horizontal = 6.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = recordMap["train"]?.toString() ?: "",
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp
                    )
                    
                    Spacer(modifier = Modifier.width(4.dp))
                    
                    val directionStr = recordMap["direction"]?.toString() ?: ""
                    val directionColor = when(directionStr) {
                        "上行" -> MaterialTheme.colorScheme.primary
                        "下行" -> MaterialTheme.colorScheme.secondary
                        else -> MaterialTheme.colorScheme.onSurface
                    }
                    
                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = directionColor.copy(alpha = 0.1f),
                        modifier = Modifier.padding(horizontal = 2.dp)
                    ) {
                        Text(
                            text = directionStr,
                            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                            fontSize = 12.sp,
                            color = directionColor
                        )
                    }
                }
                
                Text(
                    text = recordMap["timestamp"]?.toString()?.split(" ")?.getOrNull(1) ?: "",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            
            Spacer(modifier = Modifier.height(4.dp))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "速度: ${recordMap["speed"] ?: ""}",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium
                )
                
                Text(
                    text = "位置: ${recordMap["position"] ?: ""}",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium
                )
            }
            
            Spacer(modifier = Modifier.height(4.dp))
            HorizontalDivider(thickness = 0.5.dp)
            Spacer(modifier = Modifier.height(4.dp))
            
            Row(
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    CompactInfoItem(label = "机车号", value = recordMap["loco"]?.toString() ?: "")
                    CompactInfoItem(label = "线路", value = recordMap["route"]?.toString() ?: "")
                }
                
                Column(modifier = Modifier.weight(1f)) {
                    CompactInfoItem(label = "类型", value = recordMap["lbj_class"]?.toString() ?: "")
                    CompactInfoItem(label = "信号", value = recordMap["rssi"]?.toString() ?: "")
                }
            }
        }
    }
}

@Composable
private fun CompactInfoItem(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
    ) {
        Text(
            text = "$label: ",
            fontWeight = FontWeight.Medium,
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        
        Text(
            text = value,
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
} 
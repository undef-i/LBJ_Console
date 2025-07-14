package org.noxylva.lbjconsole.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    deviceName: String,
    onDeviceNameChange: (String) -> Unit,
    onApplySettings: () -> Unit
) {
    val uriHandler = LocalUriHandler.current
    
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            OutlinedTextField(
                value = deviceName,
                onValueChange = onDeviceNameChange,
                label = { Text("蓝牙设备名称") },
                modifier = Modifier.fillMaxWidth(),
            )

            Button(
                onClick = onApplySettings,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("应用设置")
            }
        }
        
        Spacer(modifier = Modifier.weight(1f))
        
        Text(
            text = "LBJ Console v0.0.1 by undef-i",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.clickable {
                uriHandler.openUri("https://github.com/undef-i")
            }
        )
    }
}

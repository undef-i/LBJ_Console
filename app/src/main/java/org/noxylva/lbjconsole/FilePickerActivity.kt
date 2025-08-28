package org.noxylva.lbjconsole

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import org.noxylva.lbjconsole.util.DatabaseExportImportUtil

class FilePickerActivity : ComponentActivity() {
    private val exportFilePicker = registerForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        uri?.let { exportDatabase(it) }
    }

    private val importFilePicker = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri?.let { importDatabase(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val action = intent.getStringExtra("action") ?: "export"
        
        setContent {
            val coroutineScope = rememberCoroutineScope()
            
            when (action) {
                "export" -> {
                    val fileName = "lbj_console_backup_${System.currentTimeMillis()}.json"
                    exportFilePicker.launch(fileName)
                }
                "import" -> {
                    importFilePicker.launch(arrayOf("application/json", "text/plain"))
                }
            }
        }
    }

    private fun exportDatabase(uri: Uri) {
        val coroutineScope = kotlinx.coroutines.MainScope()
        coroutineScope.launch {
            try {
                val databaseUtil = DatabaseExportImportUtil(this@FilePickerActivity)
                val json = databaseUtil.exportDatabase()
                
                contentResolver.openOutputStream(uri)?.use { outputStream ->
                    outputStream.write(json.toByteArray())
                }
                
                Toast.makeText(
                    this@FilePickerActivity,
                    "数据导出成功",
                    Toast.LENGTH_SHORT
                ).show()
                
            } catch (e: Exception) {
                Toast.makeText(
                    this@FilePickerActivity,
                    "导出失败: ${e.message}",
                    Toast.LENGTH_SHORT
                ).show()
            } finally {
                finish()
            }
        }
    }

    private fun importDatabase(uri: Uri) {
        val coroutineScope = kotlinx.coroutines.MainScope()
        coroutineScope.launch {
            try {
                val databaseUtil = DatabaseExportImportUtil(this@FilePickerActivity)
                val success = databaseUtil.importDatabase(uri)
                
                if (success) {
                    Toast.makeText(
                        this@FilePickerActivity,
                        "数据导入成功",
                        Toast.LENGTH_SHORT
                    ).show()
                } else {
                    Toast.makeText(
                        this@FilePickerActivity,
                        "数据导入失败",
                        Toast.LENGTH_SHORT
                    ).show()
                }
                
            } catch (e: Exception) {
                Toast.makeText(
                    this@FilePickerActivity,
                    "导入失败: ${e.message}",
                    Toast.LENGTH_SHORT
                ).show()
            } finally {
                finish()
            }
        }
    }

    companion object {
        fun createExportIntent(context: android.content.Context): Intent {
            return Intent(context, FilePickerActivity::class.java).apply {
                putExtra("action", "export")
            }
        }

        fun createImportIntent(context: android.content.Context): Intent {
            return Intent(context, FilePickerActivity::class.java).apply {
                putExtra("action", "import")
            }
        }
    }
}
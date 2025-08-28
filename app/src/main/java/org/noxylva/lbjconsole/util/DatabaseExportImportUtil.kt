package org.noxylva.lbjconsole.util

import android.content.Context
import android.net.Uri
import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.noxylva.lbjconsole.database.AppSettingsEntity
import org.noxylva.lbjconsole.database.TrainDatabase
import org.noxylva.lbjconsole.database.TrainRecordEntity
import java.io.*
import java.util.*
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class DatabaseExportImportUtil(private val context: Context) {
    private val gson = Gson()
    private val database = TrainDatabase.getDatabase(context)

    data class SimpleRecordBackup(
        val records: List<TrainRecordEntity>
    )

    suspend fun exportDatabase(): String = withContext(Dispatchers.IO) {
        try {
            val trainRecords = database.trainRecordDao().getAllRecords()
            
            val backup = SimpleRecordBackup(
                records = trainRecords
            )
            
            val json = gson.toJson(backup)
            json
        } catch (e: Exception) {
            Log.e("DatabaseExport", "导出失败", e)
            throw e
        }
    }

    suspend fun importDatabase(uri: Uri): Boolean = withContext(Dispatchers.IO) {
        try {
            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                val json = inputStream.bufferedReader().use { it.readText() }
                val backup: SimpleRecordBackup = gson.fromJson(json, object : TypeToken<SimpleRecordBackup>() {}.type)
                
                database.trainRecordDao().deleteAllRecords()
                
                if (backup.records.isNotEmpty()) {
                    database.trainRecordDao().insertRecords(backup.records)
                }
                
                true
            } ?: false
        } catch (e: Exception) {
            Log.e("DatabaseImport", "导入失败", e)
            false
        }
    }

    suspend fun getExportFileUri(): Uri {
        val filePath = exportDatabase()
        return Uri.parse("file://$filePath")
    }
}
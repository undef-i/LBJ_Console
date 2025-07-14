package org.noxylva.lbjconsole.model

import android.content.Context
import android.content.SharedPreferences
import android.os.Environment
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

class TrainRecordManager(private val context: Context) {
    companion object {
        const val TAG = "TrainRecordManager"
        const val MAX_RECORDS = 1000
        private const val PREFS_NAME = "train_records"
        private const val KEY_RECORDS = "records"
    }

    
    private val trainRecords = CopyOnWriteArrayList<TrainRecord>()
    private val recordCount = AtomicInteger(0)
    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    
    init {
        loadRecords()
    }
    
    
    private var filterTrain: String = ""
    private var filterRoute: String = ""
    private var filterDirection: String = "全部"
    
    
    fun addRecord(jsonData: JSONObject): TrainRecord {
        val record = TrainRecord(jsonData)
        trainRecords.add(0, record)
        
        
        while (trainRecords.size > MAX_RECORDS) {
            trainRecords.removeAt(trainRecords.size - 1)
        }
        
        recordCount.incrementAndGet()
        saveRecords()
        return record
    }
    
    
    fun getAllRecords(): List<TrainRecord> {
        return trainRecords
    }
    
    
    fun getFilteredRecords(): List<TrainRecord> {
        if (filterTrain.isEmpty() && filterRoute.isEmpty() && filterDirection == "全部") {
            return trainRecords
        }
        
        return trainRecords.filter { record ->
            matchFilter(record)
        }
    }
    
    
    private fun matchFilter(record: TrainRecord): Boolean {
        
        if (filterTrain.isNotEmpty() && !record.train.contains(filterTrain)) {
            return false
        }
        
        
        if (filterRoute.isNotEmpty() && !record.route.contains(filterRoute)) {
            return false
        }
        
        
        if (filterDirection != "全部") {
            val dirText = when (record.direction) {
                1 -> "下行"
                3 -> "上行"
                else -> "未知"
            }
            if (dirText != filterDirection) {
                return false
            }
        }
        
        return true
    }
    
    
    fun setFilter(train: String, route: String, direction: String) {
        filterTrain = train
        filterRoute = route
        filterDirection = direction
    }
    
    
    fun clearFilter() {
        filterTrain = ""
        filterRoute = ""
        filterDirection = "全部"
    }
    
    
    fun clearRecords() {
        trainRecords.clear()
        recordCount.set(0)
        saveRecords()
    }
    
    fun deleteRecord(record: TrainRecord): Boolean {
        val result = trainRecords.remove(record)
        if (result) {
            recordCount.decrementAndGet()
            saveRecords()
        }
        return result
    }

    fun deleteRecords(records: List<TrainRecord>): Int {
        var deletedCount = 0
        records.forEach { record ->
            if (trainRecords.remove(record)) {
                deletedCount++
            }
        }
        
        if (deletedCount > 0) {
            recordCount.addAndGet(-deletedCount)
            saveRecords()
        }
        return deletedCount
    }
    
    private fun saveRecords() {
        try {
            val jsonArray = JSONArray()
            for (record in trainRecords) {
                jsonArray.put(record.toJSON())
            }
            prefs.edit().putString(KEY_RECORDS, jsonArray.toString()).apply()
            Log.d(TAG, "Saved ${trainRecords.size} records")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save records: ${e.message}")
        }
    }
    
    
    private fun loadRecords() {
        try {
            val jsonStr = prefs.getString(KEY_RECORDS, "[]")
            val jsonArray = JSONArray(jsonStr)
            trainRecords.clear()
            
            for (i in 0 until jsonArray.length()) {
                val jsonObject = jsonArray.getJSONObject(i)
                trainRecords.add(TrainRecord(jsonObject))
            }
            
            recordCount.set(trainRecords.size)
            Log.d(TAG, "Loaded ${trainRecords.size} records")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load records: ${e.message}")
        }
    }
    
    
    fun exportToCsv(records: List<TrainRecord>): File? {
        try {
            val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val fileName = "train_records_$timeStamp.csv"
            
            
            val downloadsDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            val file = File(downloadsDir, fileName)
            
            FileWriter(file).use { writer ->
                
                writer.append("时间戳,列车号,列车类型,方向,速度,位置,时间,机车号,机车类型,路线,位置信息,信号强度\n")
                
                
                for (record in records) {
                    val map = record.toMap()
                    writer.append(map["timestamp"]).append(",")
                    writer.append(map["train"]).append(",")
                    writer.append(map["lbj_class"]).append(",")
                    writer.append(map["direction"]).append(",")
                    writer.append(map["speed"]?.replace(" km/h", "") ?: "").append(",")
                    writer.append(map["position"]?.replace(" km", "") ?: "").append(",")
                    writer.append(map["time"]).append(",")
                    writer.append(map["loco"]).append(",")
                    writer.append(map["loco_type"]).append(",")
                    writer.append(map["route"]).append(",")
                    writer.append(map["position_info"]).append(",")
                    writer.append(map["rssi"]?.replace(" dBm", "") ?: "").append("\n")
                }
            }
            
            return file
        } catch (e: Exception) {
            Log.e(TAG, "Error exporting to CSV: ${e.message}")
            return null
        }
    }
    
    
    fun getRecordCount(): Int {
        return recordCount.get()
    }
}
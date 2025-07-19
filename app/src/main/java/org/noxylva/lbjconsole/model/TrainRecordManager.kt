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
        private const val KEY_MERGE_SETTINGS = "merge_settings"
    }

    
    private val trainRecords = CopyOnWriteArrayList<TrainRecord>()
    private val recordCount = AtomicInteger(0)
    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    
    var mergeSettings = MergeSettings()
        private set
    
    init {
        loadRecords()
        loadMergeSettings()
    }
    
    
    private var filterTrain: String = ""
    private var filterRoute: String = ""
    private var filterDirection: String = "全部"
    
    
    fun addRecord(jsonData: JSONObject): TrainRecord {
        val record = TrainRecord(jsonData)
        record.receivedTimestamp = Date()
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
    

    
    
    fun getRecordCount(): Int {
        return recordCount.get()
    }
    
    fun updateMergeSettings(newSettings: MergeSettings) {
        mergeSettings = newSettings
        saveMergeSettings()
    }
    
    
    fun getMergedRecords(): List<MergedTrainRecord> {
        if (!mergeSettings.enabled) {
            return emptyList()
        }
        
        val records = getFilteredRecords()
        return processRecordsForMerging(records, mergeSettings)
    }
    
    fun getMixedRecords(): List<Any> {
        if (!mergeSettings.enabled) {
            return getFilteredRecords()
        }
        
        val allRecords = getFilteredRecords()
        val mergedRecords = processRecordsForMerging(allRecords, mergeSettings)
        
        val mergedRecordIds = mergedRecords.flatMap { merged ->
            merged.records.map { it.timestamp.time.toString() }
        }.toSet()
        
        val singleRecords = allRecords.filter { record ->
            !mergedRecordIds.contains(record.timestamp.time.toString())
        }
        
        val mixedList = mutableListOf<Any>()
        mixedList.addAll(mergedRecords)
        mixedList.addAll(singleRecords)
        
        return mixedList.sortedByDescending { item ->
            when (item) {
                is MergedTrainRecord -> item.latestRecord.timestamp
                is TrainRecord -> item.timestamp
                else -> Date(0)
            }
        }
    }
    
    private fun processRecordsForMerging(records: List<TrainRecord>, settings: MergeSettings): List<MergedTrainRecord> {
        val groupedRecords = mutableMapOf<String, MutableList<TrainRecord>>()
        val currentTime = Date()
        
        records.forEach { record ->
            val groupKey = generateGroupKey(record, settings.groupBy)
            if (groupKey != null) {
                val withinTimeWindow = settings.timeWindow.seconds?.let { windowSeconds ->
                    (currentTime.time - record.timestamp.time) / 1000 <= windowSeconds
                } ?: true
                
                if (withinTimeWindow) {
                    groupedRecords.getOrPut(groupKey) { mutableListOf() }.add(record)
                }
            }
        }
        
        return groupedRecords.mapNotNull { (groupKey, groupRecords) ->
            if (groupRecords.size >= 2) {
                val sortedRecords = groupRecords.sortedBy { it.timestamp }
                val latestRecord = sortedRecords.maxByOrNull { it.timestamp }!!
                MergedTrainRecord(
                    groupKey = groupKey,
                    records = sortedRecords,
                    latestRecord = latestRecord
                )
            } else null
        }.sortedByDescending { it.latestRecord.timestamp }
    }
    
    private fun saveMergeSettings() {
        try {
            val json = JSONObject().apply {
                put("enabled", mergeSettings.enabled)
                put("groupBy", mergeSettings.groupBy.name)
                put("timeWindow", mergeSettings.timeWindow.name)
            }
            prefs.edit().putString(KEY_MERGE_SETTINGS, json.toString()).apply()
            Log.d(TAG, "Saved merge settings")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save merge settings: ${e.message}")
        }
    }
    
    private fun loadMergeSettings() {
        try {
            val jsonStr = prefs.getString(KEY_MERGE_SETTINGS, null)
            if (jsonStr != null) {
                val json = JSONObject(jsonStr)
                mergeSettings = MergeSettings(
                    enabled = json.getBoolean("enabled"),
                    groupBy = GroupBy.valueOf(json.getString("groupBy")),
                    timeWindow = TimeWindow.valueOf(json.getString("timeWindow"))
                )
            }
            Log.d(TAG, "Loaded merge settings: $mergeSettings")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load merge settings: ${e.message}")
            mergeSettings = MergeSettings()
        }
    }
}
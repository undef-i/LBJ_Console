package org.noxylva.lbjconsole.model

import android.content.Context
import android.content.SharedPreferences
import android.os.Environment
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.noxylva.lbjconsole.database.TrainDatabase
import org.noxylva.lbjconsole.database.TrainRecordEntity
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
    private val database = TrainDatabase.getDatabase(context)
    private val trainRecordDao = database.trainRecordDao()
    private val ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    var mergeSettings = MergeSettings()
        private set
    
    init {
        ioScope.launch {
            migrateFromSharedPreferences()
            loadRecords()
            loadMergeSettings()
        }
    }
    
    private suspend fun migrateFromSharedPreferences() {
        try {
            val jsonStr = prefs.getString(KEY_RECORDS, null)
            if (jsonStr != null && jsonStr != "[]") {
                val jsonArray = JSONArray(jsonStr)
                val records = mutableListOf<TrainRecordEntity>()
                
                for (i in 0 until jsonArray.length()) {
                    val jsonObject = jsonArray.getJSONObject(i)
                    val trainRecord = TrainRecord(jsonObject)
                    records.add(TrainRecordEntity.fromTrainRecord(trainRecord))
                }
                
                if (records.isNotEmpty()) {
                    trainRecordDao.insertRecords(records)
                    prefs.edit().remove(KEY_RECORDS).apply()
                    Log.d(TAG, "Migrated ${records.size} records from SharedPreferences to Room database")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to migrate records: ${e.message}")
        }
    }
    
    
    private var filterTrain: String = ""
    private var filterRoute: String = ""
    private var filterDirection: String = "全部"
    
    
    fun addRecord(jsonData: JSONObject): TrainRecord {
        val record = TrainRecord(jsonData)
        record.receivedTimestamp = Date()
        trainRecords.add(0, record)
        
        
        while (trainRecords.size > MAX_RECORDS) {
            val removedRecord = trainRecords.removeAt(trainRecords.size - 1)
            ioScope.launch {
                trainRecordDao.deleteRecordById(removedRecord.uniqueId)
            }
        }
        
        recordCount.incrementAndGet()
        ioScope.launch {
            trainRecordDao.insertRecord(TrainRecordEntity.fromTrainRecord(record))
        }
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
    
    suspend fun getFilteredRecordsFromDatabase(): List<TrainRecord> {
        return try {
            val entities = trainRecordDao.getFilteredRecords(filterTrain, filterRoute, filterDirection)
            entities.map { it.toTrainRecord() }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get filtered records from database: ${e.message}")
            emptyList()
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
    
    
    suspend fun refreshRecordsFromDatabase() {
        try {
            val entities = trainRecordDao.getAllRecords()
            trainRecords.clear()
            entities.forEach { entity ->
                trainRecords.add(entity.toTrainRecord())
            }
            recordCount.set(trainRecords.size)
            Log.d(TAG, "Refreshed ${trainRecords.size} records from database")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to refresh records from database: ${e.message}")
        }
    }
    
    
    fun clearRecords() {
        trainRecords.clear()
        recordCount.set(0)
        ioScope.launch {
            trainRecordDao.deleteAllRecords()
        }
    }
    
    fun deleteRecord(record: TrainRecord): Boolean {
        val result = trainRecords.remove(record)
        if (result) {
            recordCount.decrementAndGet()
            ioScope.launch {
                trainRecordDao.deleteRecordById(record.uniqueId)
            }
        }
        return result
    }

    fun deleteRecords(records: List<TrainRecord>): Int {
        var deletedCount = 0
        val idsToDelete = mutableListOf<String>()
        
        records.forEach { record ->
            if (trainRecords.remove(record)) {
                deletedCount++
                idsToDelete.add(record.uniqueId)
            }
        }
        
        if (deletedCount > 0) {
            recordCount.addAndGet(-deletedCount)
            ioScope.launch {
                trainRecordDao.deleteRecordsByIds(idsToDelete)
            }
        }
        return deletedCount
    }
    
    private fun saveRecords() {
        ioScope.launch {
            try {
                val entities = trainRecords.map { TrainRecordEntity.fromTrainRecord(it) }
                trainRecordDao.insertRecords(entities)
                Log.d(TAG, "Saved ${trainRecords.size} records to database")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save records: ${e.message}")
            }
        }
    }
    
    
    private suspend fun loadRecords() {
        try {
            val entities = trainRecordDao.getAllRecords()
            trainRecords.clear()
            
            entities.forEach { entity ->
                trainRecords.add(entity.toTrainRecord())
            }
            
            recordCount.set(trainRecords.size)
            Log.d(TAG, "Loaded ${trainRecords.size} records from database")
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
            merged.records.map { it.uniqueId }
        }.toSet()
        
        val singleRecords = allRecords.filter { record ->
            !mergedRecordIds.contains(record.uniqueId)
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
        val currentTime = Date()
        val validRecords = records.filter { record ->
            settings.timeWindow.seconds?.let { windowSeconds ->
                (currentTime.time - record.timestamp.time) / 1000 <= windowSeconds
            } ?: true
        }
        
        return when (settings.groupBy) {
            GroupBy.TRAIN_OR_LOCO -> processTrainOrLocoMerging(validRecords)
            else -> {
                val groupedRecords = mutableMapOf<String, MutableList<TrainRecord>>()
                validRecords.forEach { record ->
                    val groupKey = generateGroupKey(record, settings.groupBy)
                    if (groupKey != null) {
                        groupedRecords.getOrPut(groupKey) { mutableListOf() }.add(record)
                    }
                }
                
                groupedRecords.mapNotNull { (groupKey, groupRecords) ->
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
        }
    }
    
    private fun processTrainOrLocoMerging(records: List<TrainRecord>): List<MergedTrainRecord> {
        val groups = mutableListOf<MutableList<TrainRecord>>()
        
        records.forEach { record ->
            val train = record.train.trim()
            val loco = record.loco.trim()
            
            if ((train.isEmpty() || train == "<NUL>") && (loco.isEmpty() || loco == "<NUL>")) {
                return@forEach
            }
            
            var foundGroup: MutableList<TrainRecord>? = null
            
            for (group in groups) {
                val shouldMerge = group.any { existingRecord ->
                    val existingTrain = existingRecord.train.trim()
                    val existingLoco = existingRecord.loco.trim()
                    
                    (train.isNotEmpty() && train != "<NUL>" && train == existingTrain) ||
                    (loco.isNotEmpty() && loco != "<NUL>" && loco == existingLoco)
                }
                
                if (shouldMerge) {
                    foundGroup = group
                    break
                }
            }
            
            if (foundGroup != null) {
                foundGroup.add(record)
            } else {
                groups.add(mutableListOf(record))
            }
        }
        
        return groups.mapNotNull { groupRecords ->
            if (groupRecords.size >= 2) {
                val sortedRecords = groupRecords.sortedBy { it.timestamp }
                val latestRecord = sortedRecords.maxByOrNull { it.timestamp }!!
                val groupKey = "${latestRecord.train}_OR_${latestRecord.loco}"
                MergedTrainRecord(
                    groupKey = groupKey,
                    records = sortedRecords,
                    latestRecord = latestRecord
                )
            } else null
        }.sortedByDescending { it.latestRecord.timestamp }
    }
    
    private fun saveMergeSettings() {
        ioScope.launch {
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
    
    suspend fun exportRecordsToJson(): JSONArray {
        val jsonArray = JSONArray()
        try {
            val entities = trainRecordDao.getAllRecords()
            entities.forEach { entity ->
                val record = entity.toTrainRecord()
                jsonArray.put(record.toJSON())
            }
            Log.d(TAG, "Exported ${entities.size} records to JSON")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to export records to JSON: ${e.message}")
        }
        return jsonArray
    }
    
    suspend fun importRecordsFromJson(jsonArray: JSONArray): Int {
        var importedCount = 0
        try {
            val records = mutableListOf<TrainRecordEntity>()
            for (i in 0 until jsonArray.length()) {
                val jsonObject = jsonArray.getJSONObject(i)
                val trainRecord = TrainRecord(jsonObject)
                records.add(TrainRecordEntity.fromTrainRecord(trainRecord))
            }
            
            if (records.isNotEmpty()) {
                trainRecordDao.insertRecords(records)
                importedCount = records.size
                refreshRecordsFromDatabase()
                Log.d(TAG, "Imported $importedCount records from JSON")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to import records from JSON: ${e.message}")
        }
        return importedCount
    }
}
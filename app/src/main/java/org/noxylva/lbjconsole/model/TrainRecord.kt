package org.noxylva.lbjconsole.model

import android.util.Log
import org.json.JSONObject
import java.util.*
import org.osmdroid.util.GeoPoint
import org.noxylva.lbjconsole.util.LocationUtils

class TrainRecord(jsonData: JSONObject? = null) {
    companion object {
        const val TAG = "TrainRecord"
    }
    
    var timestamp: Date = Date()
    var receivedTimestamp: Date = Date()
    var train: String = ""
    var direction: Int = 0
    var speed: String = ""
    var position: String = ""
    var time: String = ""
    var loco: String = ""
    var locoType: String = ""
    var lbjClass: String = ""
    var route: String = ""
    var positionInfo: String = ""
    var rssi: Double = 0.0

    
    private var _coordinates: GeoPoint? = null

    init {
        jsonData?.let {
            try {
                if (jsonData.has("timestamp")) {
                    
                    timestamp = Date(jsonData.getLong("timestamp"))
                }
            
                if (jsonData.has("receivedTimestamp")) {
                    receivedTimestamp = Date(jsonData.getLong("receivedTimestamp"))
                } else {
                    receivedTimestamp = if (jsonData.has("timestamp")) {
                        Date(jsonData.getLong("timestamp"))
                    } else {
                        Date()
                    }
                }
                
                updateFromJson(it)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize TrainRecord from JSON: ${e.message}")
            }
        }
    }

    fun updateFromJson(jsonData: JSONObject) {
        try {
            Log.d(TAG, "Parsing JSON: ${jsonData.toString().take(100)}...")
            
            train = jsonData.optString("train", "")
            direction = jsonData.optInt("dir", 0)
            speed = jsonData.optString("speed", "")
            position = jsonData.optString("pos", "")
            time = jsonData.optString("time", "")
            loco = jsonData.optString("loco", "")
            locoType = jsonData.optString("loco_type", "")
            lbjClass = jsonData.optString("lbj_class", "")
            route = jsonData.optString("route", "")
            positionInfo = jsonData.optString("position_info", "")
            rssi = jsonData.optDouble("rssi", 0.0)
            
            
            _coordinates = null
            
            Log.d(TAG, "Successfully parsed: train=$train, dir=$direction, speed=$speed")
        } catch (e: Exception) {
            Log.e(TAG, "JSON parse error: ${e.message}", e)
            
            
            try { train = jsonData.optString("train", "") } catch (e: Exception) { }
            try { direction = jsonData.optInt("dir", 0) } catch (e: Exception) { }
            try { speed = jsonData.optString("speed", "") } catch (e: Exception) { }
            try { position = jsonData.optString("pos", "") } catch (e: Exception) { }
            try { time = jsonData.optString("time", "") } catch (e: Exception) { }
            
            Log.d(TAG, "Attempting field-level parse: train=$train, dir=$direction")
        }
    }

    
    fun getCoordinates(): GeoPoint? {
        
        if (_coordinates != null) {
            return _coordinates
        }
        
        
        _coordinates = LocationUtils.parsePositionInfo(positionInfo)
        return _coordinates
    }
    private fun isValidValue(value: String): Boolean {
        val trimmed = value.trim()
        return trimmed.isNotEmpty() &&
               trimmed != "NUL" &&
               trimmed != "<NUL>" &&
               trimmed != "NA" &&
               trimmed != "<NA>" &&
               !trimmed.all { it == '*' }
    }

    fun toMap(showDetailedTime: Boolean = false): Map<String, String> {
        val directionText = when (direction) {
            1 -> "下行"
            3 -> "上行"
            else -> "未知"
        }
        
        
        val trainDisplay = if (isValidValue(lbjClass) && isValidValue(train)) {
            "${lbjClass.trim()}${train.trim()}"
        } else if (isValidValue(lbjClass)) {
            lbjClass.trim()
        } else if (isValidValue(train)) {
            train.trim()
        } else ""
        
        val map = mutableMapOf<String, String>()
        
        val dateFormat = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
        map["timestamp"] = dateFormat.format(timestamp)
        map["receivedTimestamp"] = dateFormat.format(receivedTimestamp)
        
        
        if (trainDisplay.isNotEmpty()) map["train"] = trainDisplay
        if (directionText != "未知") map["direction"] = directionText
        if (isValidValue(speed)) map["speed"] = "速度: ${speed.trim()} km/h"
        if (isValidValue(position)) map["position"] = "位置: ${position.trim()} km"
        val timeToDisplay = if (showDetailedTime) {
            val dateFormat = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
            if (isValidValue(time)) {
                "列车时间: $time\n接收时间: ${dateFormat.format(receivedTimestamp)}"
            } else {
                dateFormat.format(receivedTimestamp)
            }
        } else {
            val currentTime = System.currentTimeMillis()
            val diffInSec = (currentTime - receivedTimestamp.time) / 1000
            when {
                diffInSec < 60 -> "${diffInSec}秒前"
                diffInSec < 3600 -> "${diffInSec / 60}分钟前"
                else -> "${diffInSec / 3600}小时前"
            }
        }
        map["time"] = timeToDisplay
        if (isValidValue(loco)) map["loco"] = "机车号: ${loco.trim()}"
        if (isValidValue(locoType)) map["loco_type"] = "型号: ${locoType.trim()}"
        if (isValidValue(route)) map["route"] = "线路: ${route.trim()}"
        if (isValidValue(positionInfo) && !positionInfo.trim().matches(Regex(".*(<NUL>|\\s)*.*"))) {
            map["position_info"] = "位置信息: ${positionInfo.trim()}"
        }
        if (rssi != 0.0) map["rssi"] = "信号强度: $rssi dBm"
        
        return map
    }

    
    fun toJSON(): JSONObject {
        val json = JSONObject()
        json.put("timestamp", timestamp.time)  
        json.put("receivedTimestamp", receivedTimestamp.time)
        json.put("train", train)
        json.put("dir", direction)  
        json.put("speed", speed)
        json.put("pos", position)
        json.put("time", time)
        json.put("loco", loco)
        json.put("loco_type", locoType)
        json.put("lbj_class", lbjClass)
        json.put("route", route)
        json.put("position_info", positionInfo)
        json.put("rssi", rssi)
        return json
    }
}
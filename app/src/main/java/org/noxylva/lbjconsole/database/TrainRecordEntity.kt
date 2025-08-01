package org.noxylva.lbjconsole.database

import androidx.room.Entity
import androidx.room.PrimaryKey
import org.noxylva.lbjconsole.model.TrainRecord
import org.json.JSONObject
import java.util.*

@Entity(tableName = "train_records")
data class TrainRecordEntity(
    @PrimaryKey val uniqueId: String,
    val timestamp: Long,
    val receivedTimestamp: Long,
    val train: String,
    val direction: Int,
    val speed: String,
    val position: String,
    val time: String,
    val loco: String,
    val locoType: String,
    val lbjClass: String,
    val route: String,
    val positionInfo: String,
    val rssi: Double
) {
    fun toTrainRecord(): TrainRecord {
        val jsonData = JSONObject().apply {
            put("uniqueId", uniqueId)
            put("timestamp", timestamp)
            put("receivedTimestamp", receivedTimestamp)
            put("train", train)
            put("dir", direction)
            put("speed", speed)
            put("pos", position)
            put("time", time)
            put("loco", loco)
            put("loco_type", locoType)
            put("lbj_class", lbjClass)
            put("route", route)
            put("position_info", positionInfo)
            put("rssi", rssi)
        }
        return TrainRecord(jsonData)
    }
    
    companion object {
        fun fromTrainRecord(record: TrainRecord): TrainRecordEntity {
            return TrainRecordEntity(
                uniqueId = record.uniqueId,
                timestamp = record.timestamp.time,
                receivedTimestamp = record.receivedTimestamp.time,
                train = record.train,
                direction = record.direction,
                speed = record.speed,
                position = record.position,
                time = record.time,
                loco = record.loco,
                locoType = record.locoType,
                lbjClass = record.lbjClass,
                route = record.route,
                positionInfo = record.positionInfo,
                rssi = record.rssi
            )
        }
    }
}
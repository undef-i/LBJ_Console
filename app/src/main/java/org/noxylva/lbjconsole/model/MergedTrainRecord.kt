package org.noxylva.lbjconsole.model

import java.util.*

data class MergedTrainRecord(
    val groupKey: String,
    val records: List<TrainRecord>,
    val latestRecord: TrainRecord
) {
    val recordCount: Int get() = records.size
    val timeSpan: Pair<Date, Date> get() = 
        records.minByOrNull { it.timestamp }!!.timestamp to 
        records.maxByOrNull { it.timestamp }!!.timestamp
    
    fun getAllCoordinates() = records.mapNotNull { it.getCoordinates() }
    
    fun getUniqueRoutes() = records.map { it.route }.filter { it.isNotEmpty() && it != "<NUL>" }.toSet()
    
    fun getUniquePositions() = records.map { it.position }.filter { it.isNotEmpty() && it != "<NUL>" }.toSet()
}
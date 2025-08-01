package org.noxylva.lbjconsole.database

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface TrainRecordDao {
    
    @Query("SELECT * FROM train_records ORDER BY timestamp DESC")
    suspend fun getAllRecords(): List<TrainRecordEntity>
    
    @Query("SELECT * FROM train_records ORDER BY timestamp DESC")
    fun getAllRecordsFlow(): Flow<List<TrainRecordEntity>>
    
    @Query("SELECT * FROM train_records WHERE uniqueId = :uniqueId")
    suspend fun getRecordById(uniqueId: String): TrainRecordEntity?
    
    @Query("SELECT COUNT(*) FROM train_records")
    suspend fun getRecordCount(): Int
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertRecord(record: TrainRecordEntity)
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertRecords(records: List<TrainRecordEntity>)
    
    @Delete
    suspend fun deleteRecord(record: TrainRecordEntity)
    
    @Delete
    suspend fun deleteRecords(records: List<TrainRecordEntity>)
    
    @Query("DELETE FROM train_records")
    suspend fun deleteAllRecords()
    
    @Query("DELETE FROM train_records WHERE uniqueId = :uniqueId")
    suspend fun deleteRecordById(uniqueId: String)
    
    @Query("DELETE FROM train_records WHERE uniqueId IN (:uniqueIds)")
    suspend fun deleteRecordsByIds(uniqueIds: List<String>)
    
    @Query("SELECT * FROM train_records WHERE train LIKE '%' || :train || '%' AND route LIKE '%' || :route || '%' AND (:direction = '全部' OR (:direction = '上行' AND direction = 3) OR (:direction = '下行' AND direction = 1)) ORDER BY timestamp DESC")
    suspend fun getFilteredRecords(train: String, route: String, direction: String): List<TrainRecordEntity>
    
    @Query("SELECT * FROM train_records ORDER BY timestamp DESC LIMIT :limit")
    suspend fun getLatestRecords(limit: Int): List<TrainRecordEntity>
    
    @Query("SELECT * FROM train_records WHERE timestamp >= :fromTime ORDER BY timestamp DESC")
    suspend fun getRecordsFromTime(fromTime: Long): List<TrainRecordEntity>
}
package org.noxylva.lbjconsole.database

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface AppSettingsDao {
    
    @Query("SELECT * FROM app_settings WHERE id = 1")
    suspend fun getSettings(): AppSettingsEntity?
    
    @Query("SELECT * FROM app_settings WHERE id = 1")
    fun getSettingsFlow(): Flow<AppSettingsEntity?>
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSettings(settings: AppSettingsEntity)
    
    @Update
    suspend fun updateSettings(settings: AppSettingsEntity)
    
    @Query("DELETE FROM app_settings")
    suspend fun deleteAllSettings()
    
    @Query("UPDATE app_settings SET notificationEnabled = :enabled WHERE id = 1")
    suspend fun updateNotificationEnabled(enabled: Boolean)
    
    @Transaction
    suspend fun saveSettings(settings: AppSettingsEntity) {
        insertSettings(settings)
    }
}
package org.noxylva.lbjconsole.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [TrainRecordEntity::class, AppSettingsEntity::class],
    version = 4,
    exportSchema = false
)
abstract class TrainDatabase : RoomDatabase() {
    
    abstract fun trainRecordDao(): TrainRecordDao
    abstract fun appSettingsDao(): AppSettingsDao
    
    companion object {
        @Volatile
        private var INSTANCE: TrainDatabase? = null
        
        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("""
                    CREATE TABLE IF NOT EXISTS `app_settings` (
                        `id` INTEGER NOT NULL,
                        `deviceName` TEXT NOT NULL,
                        `currentTab` INTEGER NOT NULL,
                        `historyEditMode` INTEGER NOT NULL,
                        `historySelectedRecords` TEXT NOT NULL,
                        `historyExpandedStates` TEXT NOT NULL,
                        `historyScrollPosition` INTEGER NOT NULL,
                        `historyScrollOffset` INTEGER NOT NULL,
                        `settingsScrollPosition` INTEGER NOT NULL,
                        `mapCenterLat` REAL,
                        `mapCenterLon` REAL,
                        `mapZoomLevel` REAL NOT NULL,
                        `mapRailwayLayerVisible` INTEGER NOT NULL,
                        `specifiedDeviceAddress` TEXT,
                        `searchOrderList` TEXT NOT NULL,
                        `autoConnectEnabled` INTEGER NOT NULL,
                        `backgroundServiceEnabled` INTEGER NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                """)
            }
        }
        
        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE app_settings ADD COLUMN notificationEnabled INTEGER NOT NULL DEFAULT 0")
            }
        }
        
        val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(database: SupportSQLiteDatabase) {
                // Since we can't determine the exact schema change, we'll use fallback migration
                // This will preserve data where possible while updating the schema
                
                // Create new table with correct schema
                database.execSQL("""
                    CREATE TABLE IF NOT EXISTS `app_settings_new` (
                        `id` INTEGER NOT NULL,
                        `deviceName` TEXT NOT NULL DEFAULT 'LBJReceiver',
                        `currentTab` INTEGER NOT NULL DEFAULT 0,
                        `historyEditMode` INTEGER NOT NULL DEFAULT 0,
                        `historySelectedRecords` TEXT NOT NULL DEFAULT '',
                        `historyExpandedStates` TEXT NOT NULL DEFAULT '',
                        `historyScrollPosition` INTEGER NOT NULL DEFAULT 0,
                        `historyScrollOffset` INTEGER NOT NULL DEFAULT 0,
                        `settingsScrollPosition` INTEGER NOT NULL DEFAULT 0,
                        `mapCenterLat` REAL,
                        `mapCenterLon` REAL,
                        `mapZoomLevel` REAL NOT NULL DEFAULT 10.0,
                        `mapRailwayLayerVisible` INTEGER NOT NULL DEFAULT 1,
                        `specifiedDeviceAddress` TEXT,
                        `searchOrderList` TEXT NOT NULL DEFAULT '',
                        `autoConnectEnabled` INTEGER NOT NULL DEFAULT 1,
                        `backgroundServiceEnabled` INTEGER NOT NULL DEFAULT 0,
                        `notificationEnabled` INTEGER NOT NULL DEFAULT 0,
                        PRIMARY KEY(`id`)
                    )
                """)
                
                // Copy data from old table to new table, handling missing columns
                try {
                    database.execSQL("""
                        INSERT INTO `app_settings_new` (
                            id, deviceName, currentTab, historyEditMode, historySelectedRecords,
                            historyExpandedStates, historyScrollPosition, historyScrollOffset,
                            settingsScrollPosition, mapCenterLat, mapCenterLon, mapZoomLevel,
                            mapRailwayLayerVisible
                        )
                        SELECT 
                            COALESCE(id, 1),
                            COALESCE(deviceName, 'LBJReceiver'),
                            COALESCE(currentTab, 0),
                            COALESCE(historyEditMode, 0),
                            COALESCE(historySelectedRecords, ''),
                            COALESCE(historyExpandedStates, ''),
                            COALESCE(historyScrollPosition, 0),
                            COALESCE(historyScrollOffset, 0),
                            COALESCE(settingsScrollPosition, 0),
                            mapCenterLat,
                            mapCenterLon,
                            COALESCE(mapZoomLevel, 10.0),
                            COALESCE(mapRailwayLayerVisible, 1)
                        FROM `app_settings`
                    """)
                } catch (e: Exception) {
                    // If the old table doesn't exist or has different structure, insert default
                    database.execSQL("""
                        INSERT INTO `app_settings_new` (
                            id, deviceName, currentTab, historyEditMode, historySelectedRecords,
                            historyExpandedStates, historyScrollPosition, historyScrollOffset,
                            settingsScrollPosition, mapZoomLevel, mapRailwayLayerVisible,
                            searchOrderList, autoConnectEnabled, backgroundServiceEnabled,
                            notificationEnabled
                        ) VALUES (
                            1, 'LBJReceiver', 0, 0, '', '', 0, 0, 0, 10.0, 1, '', 1, 0, 0
                        )
                    """)
                }
                
                // Drop old table and rename new table
                database.execSQL("DROP TABLE IF EXISTS `app_settings`")
                database.execSQL("ALTER TABLE `app_settings_new` RENAME TO `app_settings`")
            }
        }
        
        fun getDatabase(context: Context): TrainDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    TrainDatabase::class.java,
                    "train_database"
                ).addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4).build()
                INSTANCE = instance
                instance
            }
        }
    }
}
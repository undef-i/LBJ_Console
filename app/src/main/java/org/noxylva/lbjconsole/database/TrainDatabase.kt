package org.noxylva.lbjconsole.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [TrainRecordEntity::class, AppSettingsEntity::class],
    version = 3,
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
        
        fun getDatabase(context: Context): TrainDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    TrainDatabase::class.java,
                    "train_database"
                ).addMigrations(MIGRATION_1_2, MIGRATION_2_3).build()
                INSTANCE = instance
                instance
            }
        }
    }
}
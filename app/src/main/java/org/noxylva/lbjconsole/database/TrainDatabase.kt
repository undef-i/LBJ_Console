package org.noxylva.lbjconsole.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [TrainRecordEntity::class],
    version = 1,
    exportSchema = false
)
abstract class TrainDatabase : RoomDatabase() {
    
    abstract fun trainRecordDao(): TrainRecordDao
    
    companion object {
        @Volatile
        private var INSTANCE: TrainDatabase? = null
        
        fun getDatabase(context: Context): TrainDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    TrainDatabase::class.java,
                    "train_database"
                ).build()
                INSTANCE = instance
                instance
            }
        }
    }
}
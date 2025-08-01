package org.noxylva.lbjconsole.database

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "app_settings")
data class AppSettingsEntity(
    @PrimaryKey val id: Int = 1,
    val deviceName: String = "LBJReceiver",
    val currentTab: Int = 0,
    val historyEditMode: Boolean = false,
    val historySelectedRecords: String = "",
    val historyExpandedStates: String = "",
    val historyScrollPosition: Int = 0,
    val historyScrollOffset: Int = 0,
    val settingsScrollPosition: Int = 0,
    val mapCenterLat: Float? = null,
    val mapCenterLon: Float? = null,
    val mapZoomLevel: Float = 10.0f,
    val mapRailwayLayerVisible: Boolean = true,
    val specifiedDeviceAddress: String? = null,
    val searchOrderList: String = "",
    val autoConnectEnabled: Boolean = true,
    val backgroundServiceEnabled: Boolean = false,
    val notificationEnabled: Boolean = false
)
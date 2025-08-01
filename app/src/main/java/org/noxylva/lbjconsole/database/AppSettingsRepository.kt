package org.noxylva.lbjconsole.database

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first

class AppSettingsRepository(private val context: Context) {
    private val dao = TrainDatabase.getDatabase(context).appSettingsDao()
    private val sharedPrefs: SharedPreferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    
    suspend fun getSettings(): AppSettingsEntity {
        var settings = dao.getSettings()
        
        if (settings == null) {
            settings = migrateFromSharedPreferences()
            dao.saveSettings(settings)
        }
        
        return settings
    }
    
    fun getSettingsFlow(): Flow<AppSettingsEntity?> {
        return dao.getSettingsFlow()
    }
    
    suspend fun saveSettings(settings: AppSettingsEntity) {
        dao.saveSettings(settings)
    }
    
    suspend fun updateDeviceName(deviceName: String) {
        val current = getSettings()
        saveSettings(current.copy(deviceName = deviceName))
    }
    
    suspend fun updateCurrentTab(tab: Int) {
        val current = getSettings()
        saveSettings(current.copy(currentTab = tab))
    }
    
    suspend fun updateHistoryEditMode(editMode: Boolean) {
        val current = getSettings()
        saveSettings(current.copy(historyEditMode = editMode))
    }
    
    suspend fun updateHistorySelectedRecords(selectedRecords: String) {
        val current = getSettings()
        saveSettings(current.copy(historySelectedRecords = selectedRecords))
    }
    
    suspend fun updateHistoryExpandedStates(expandedStates: String) {
        val current = getSettings()
        saveSettings(current.copy(historyExpandedStates = expandedStates))
    }
    
    suspend fun updateHistoryScrollPosition(position: Int, offset: Int = 0) {
        val current = getSettings()
        saveSettings(current.copy(historyScrollPosition = position, historyScrollOffset = offset))
    }
    
    suspend fun updateSettingsScrollPosition(position: Int) {
        val current = getSettings()
        saveSettings(current.copy(settingsScrollPosition = position))
    }
    
    suspend fun updateMapSettings(centerLat: Float?, centerLon: Float?, zoomLevel: Float, railwayLayerVisible: Boolean) {
        val current = getSettings()
        saveSettings(current.copy(
            mapCenterLat = centerLat,
            mapCenterLon = centerLon,
            mapZoomLevel = zoomLevel,
            mapRailwayLayerVisible = railwayLayerVisible
        ))
    }
    
    suspend fun updateSpecifiedDeviceAddress(address: String?) {
        val current = getSettings()
        saveSettings(current.copy(specifiedDeviceAddress = address))
    }
    
    suspend fun updateSearchOrderList(orderList: String) {
        val current = getSettings()
        saveSettings(current.copy(searchOrderList = orderList))
    }
    
    suspend fun updateAutoConnectEnabled(enabled: Boolean) {
        val current = getSettings()
        saveSettings(current.copy(autoConnectEnabled = enabled))
    }
    
    suspend fun updateBackgroundServiceEnabled(enabled: Boolean) {
        val current = getSettings()
        saveSettings(current.copy(backgroundServiceEnabled = enabled))
    }
    
    suspend fun updateNotificationEnabled(enabled: Boolean) {
        val current = getSettings()
        saveSettings(current.copy(notificationEnabled = enabled))
    }
    
    private fun migrateFromSharedPreferences(): AppSettingsEntity {
        return AppSettingsEntity(
            deviceName = sharedPrefs.getString("device_name", "LBJReceiver") ?: "LBJReceiver",
            currentTab = sharedPrefs.getInt("current_tab", 0),
            historyEditMode = sharedPrefs.getBoolean("history_edit_mode", false),
            historySelectedRecords = sharedPrefs.getString("history_selected_records", "") ?: "",
            historyExpandedStates = sharedPrefs.getString("history_expanded_states", "") ?: "",
            historyScrollPosition = sharedPrefs.getInt("history_scroll_position", 0),
            historyScrollOffset = sharedPrefs.getInt("history_scroll_offset", 0),
            settingsScrollPosition = sharedPrefs.getInt("settings_scroll_position", 0),
            mapCenterLat = if (sharedPrefs.contains("map_center_lat")) sharedPrefs.getFloat("map_center_lat", 0f) else null,
            mapCenterLon = if (sharedPrefs.contains("map_center_lon")) sharedPrefs.getFloat("map_center_lon", 0f) else null,
            mapZoomLevel = sharedPrefs.getFloat("map_zoom_level", 10.0f),
            mapRailwayLayerVisible = sharedPrefs.getBoolean("map_railway_layer_visible", true),
            specifiedDeviceAddress = sharedPrefs.getString("specified_device_address", null),
            searchOrderList = sharedPrefs.getString("search_order_list", "") ?: "",
            autoConnectEnabled = sharedPrefs.getBoolean("auto_connect_enabled", true),
            backgroundServiceEnabled = sharedPrefs.getBoolean("background_service_enabled", false),
            notificationEnabled = context.getSharedPreferences("notification_settings", Context.MODE_PRIVATE)
                .getBoolean("notifications_enabled", false)
        )
    }
    
    suspend fun clearSharedPreferences() {
        sharedPrefs.edit().clear().apply()
    }
}
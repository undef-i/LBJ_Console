package org.noxylva.lbjconsole

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.widget.Switch
import androidx.appcompat.app.AppCompatActivity

class SettingsActivity : AppCompatActivity() {
    
    companion object {
        private const val PREFS_NAME = "lbj_console_settings"
        private const val KEY_BACKGROUND_SERVICE = "background_service_enabled"
        
        fun isBackgroundServiceEnabled(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return prefs.getBoolean(KEY_BACKGROUND_SERVICE, false)
        }
        
        fun setBackgroundServiceEnabled(context: Context, enabled: Boolean) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putBoolean(KEY_BACKGROUND_SERVICE, enabled).apply()
        }
    }
    
    private lateinit var backgroundServiceSwitch: Switch
    private lateinit var prefs: SharedPreferences
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.title = "Settings"
        
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        initViews()
        setupListeners()
    }
    
    private fun initViews() {
        backgroundServiceSwitch = findViewById(R.id.switch_background_service)
        backgroundServiceSwitch.isChecked = isBackgroundServiceEnabled(this)
    }
    
    private fun setupListeners() {
        backgroundServiceSwitch.setOnCheckedChangeListener { _, isChecked ->
            setBackgroundServiceEnabled(this, isChecked)
            
            if (isChecked) {
                BackgroundService.startService(this)
            } else {
                BackgroundService.stopService(this)
            }
        }
    }
    
    override fun onSupportNavigateUp(): Boolean {
        onBackPressed()
        return true
    }
}
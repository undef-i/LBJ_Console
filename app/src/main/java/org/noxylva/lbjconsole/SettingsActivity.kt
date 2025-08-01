package org.noxylva.lbjconsole

import android.content.Context
import android.os.Bundle
import android.widget.Switch
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import org.noxylva.lbjconsole.database.AppSettingsRepository

class SettingsActivity : AppCompatActivity() {
    
    companion object {
        suspend fun isBackgroundServiceEnabled(context: Context): Boolean {
            val repository = AppSettingsRepository(context)
            return repository.getSettings().backgroundServiceEnabled
        }
        
        suspend fun setBackgroundServiceEnabled(context: Context, enabled: Boolean) {
            val repository = AppSettingsRepository(context)
            repository.updateBackgroundServiceEnabled(enabled)
        }
    }
    
    private lateinit var backgroundServiceSwitch: Switch
    private lateinit var appSettingsRepository: AppSettingsRepository
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.title = "Settings"
        
        appSettingsRepository = AppSettingsRepository(this)
        
        initViews()
        setupListeners()
    }
    
    private fun initViews() {
        backgroundServiceSwitch = findViewById(R.id.switch_background_service)
        lifecycleScope.launch {
            backgroundServiceSwitch.isChecked = isBackgroundServiceEnabled(this@SettingsActivity)
        }
    }
    
    private fun setupListeners() {
        backgroundServiceSwitch.setOnCheckedChangeListener { _, isChecked ->
            lifecycleScope.launch {
                setBackgroundServiceEnabled(this@SettingsActivity, isChecked)
            }
            
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
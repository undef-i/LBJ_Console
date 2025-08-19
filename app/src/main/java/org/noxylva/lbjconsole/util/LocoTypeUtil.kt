package org.noxylva.lbjconsole.util

import android.content.Context
import java.io.BufferedReader
import java.io.InputStreamReader

class LocoTypeUtil(private val context: Context) {
    private val locoTypeMap = mutableMapOf<String, String>()
    
    init {
        loadLocoTypeMapping()
    }
    
    private fun loadLocoTypeMapping() {
        try {
            context.assets.open("loco_number_info.csv").use { inputStream ->
                BufferedReader(InputStreamReader(inputStream)).use { reader ->
                    reader.lines().forEach { line ->
                        val parts = line.split(",")
                        if (parts.size >= 2) {
                            val code = parts[0].trim()
                            val type = parts[1].trim()
                            locoTypeMap[code] = type
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    fun getLocoTypeByCode(code: String): String? {
        return locoTypeMap[code]
    }
    
    fun getLocoTypeByLocoNumber(locoNumber: String): String? {
        if (locoNumber.length < 3) return null
        val prefix = locoNumber.take(3)
        return getLocoTypeByCode(prefix)
    }
}
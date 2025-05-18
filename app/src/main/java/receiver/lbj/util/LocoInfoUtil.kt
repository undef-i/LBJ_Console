package receiver.lbj.util

import android.content.Context
import android.util.Log
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext


class LocoInfoUtil(private val context: Context) {
    
    
    data class LocoInfo(
        val model: String,
        val start: Int,
        val end: Int,
        val owner: String,
        val alias: String = "",
        val manufacturer: String = ""
    )
    
    
    private var locoData: List<LocoInfo> = emptyList()
    
    
    suspend fun loadLocoData() = withContext(Dispatchers.IO) {
        try {
            val inputStream = context.assets.open("loco_info.csv")
            val reader = BufferedReader(InputStreamReader(inputStream))
            val data = mutableListOf<LocoInfo>()
            
            reader.lineSequence().forEach { line ->
                val fields = line.split(",").map { it.trim() }
                if (fields.size >= 4) {
                    try {
                        val model = fields[0]
                        val start = fields[1].toInt()
                        val end = fields[2].toInt()
                        val owner = fields[3]
                        val alias = if (fields.size > 4) fields[4] else ""
                        val manufacturer = if (fields.size > 5) fields[5] else ""
                        
                        data.add(LocoInfo(model, start, end, owner, alias, manufacturer))
                    } catch (e: Exception) {
                        Log.e("LocoInfoUtil", "CSV parse error line=$line", e)
                    }
                }
            }
            
            reader.close()
            locoData = data
            Log.d("LocoInfoUtil", "Loaded records=${data.size}")
        } catch (e: Exception) {
            Log.e("LocoInfoUtil", "Load CSV failed", e)
            locoData = emptyList()
        }
    }
    
    
    suspend fun refreshData() {
        loadLocoData()
    }
    
    
    fun findLocoInfo(model: String, number: String): LocoInfo? {
        if (model.isEmpty() || number.isEmpty()) {
            Log.d("LocoInfoUtil", "Query failed empty model/number")
            return null
        }
        
        
        try {
            
            val cleanNumber = number.trim().replace("-", "").replace(" ", "")
            val num = if (cleanNumber.length > 4) {
                cleanNumber.takeLast(4).toInt()
            } else {
                cleanNumber.toInt()
            }
            
            locoData.forEach { info ->
                if (info.model == model) {
                    val inRange = num in info.start..info.end
                    Log.d("LocoInfoUtil", "Checking model=${info.model} range=${info.start}-${info.end} num=$num match=$inRange")
                    if (inRange) {
                        Log.d("LocoInfoUtil", "Matched owner=${info.owner} alias=${info.alias}")
                    }
                }
            }
            
            return locoData.find { info ->
                info.model == model && num in info.start..info.end
            }
        } catch (e: Exception) {
            Log.e("LocoInfoUtil", "Query failed model=$model number=$number", e)
            return null
        }
    }
    
    fun getLocoInfoDisplay(model: String, number: String): String? {
        val info = findLocoInfo(model, number) ?: return null
        
        val sb = StringBuilder()
        sb.append(info.owner)
        
        if (info.alias.isNotEmpty()) {
            sb.append(" - ${info.alias}")
        }
        
        if (info.manufacturer.isNotEmpty()) {
            sb.append(" - ${info.manufacturer}")
        }
        
        return sb.toString()
    }
}
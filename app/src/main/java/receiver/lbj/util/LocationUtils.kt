package receiver.lbj.util

import android.util.Log
import org.osmdroid.util.GeoPoint
import kotlin.math.abs


object LocationUtils {
    private const val TAG = "LocationUtils"

    
    fun parsePositionInfo(positionInfo: String): GeoPoint? {
        try {
            if (positionInfo.isEmpty() || positionInfo == "--") {
                return null
            }
            
            Log.d(TAG, "Parsing position info=$positionInfo")
            
            
            val parts = positionInfo.split(" ")
            if (parts.size != 2) {
                Log.e(TAG, "Invalid position format=$positionInfo")
                return null
            }
            
            val latitude = convertDmsToDecimal(parts[0])
            val longitude = convertDmsToDecimal(parts[1])
            
            if (latitude != null && longitude != null) {
                Log.d(TAG, "Parsed coordinates lat=$latitude lon=$longitude")
                return GeoPoint(latitude, longitude)
            }
            
            return null
        } catch (e: Exception) {
            Log.e(TAG, "Position parse error: ${e.message}", e)
            return null
        }
    }
    
    
    private fun convertDmsToDecimal(dmsString: String): Double? {
        try {
            
            val degreeIndex = dmsString.indexOf('°')
            if (degreeIndex == -1) {
                return null
            }
            
            val degrees = dmsString.substring(0, degreeIndex).toDouble()
            
            
            val minuteEndIndex = dmsString.indexOf('′')
            if (minuteEndIndex == -1) {
                return degrees
            }
            
            val minutes = dmsString.substring(degreeIndex + 1, minuteEndIndex).toDouble()
            
            
            val decimalDegrees = degrees + (minutes / 60.0)
            
            return decimalDegrees
        } catch (e: Exception) {
            Log.e(TAG, "转换DMS到十进制度出错: ${e.message}", e)
            return null
        }
    }
} 
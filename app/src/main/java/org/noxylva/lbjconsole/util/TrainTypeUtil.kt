package org.noxylva.lbjconsole.util

import android.content.Context
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.regex.Pattern

class TrainTypeUtil(private val context: Context) {
    private val trainTypePatterns = mutableListOf<Pair<Pattern, String>>()
    
    init {
        loadTrainTypePatterns()
    }
    
    private fun loadTrainTypePatterns() {
        try {
            val inputStream = context.assets.open("train_number_info.csv")
            val reader = BufferedReader(InputStreamReader(inputStream))
            
            reader.useLines { lines ->
                lines.forEach { line ->
                    if (line.isNotBlank()) {
                        val firstQuoteEnd = line.indexOf('"', 1)
                        if (firstQuoteEnd > 0 && firstQuoteEnd < line.length - 1) {
                            val regex = line.substring(1, firstQuoteEnd)
                            val remainingPart = line.substring(firstQuoteEnd + 1).trim()
                            if (remainingPart.startsWith(",\"") && remainingPart.endsWith("\"")) {
                                val type = remainingPart.substring(2, remainingPart.length - 1)
                                try {
                                    val pattern = Pattern.compile(regex)
                                    trainTypePatterns.add(Pair(pattern, type))
                                } catch (e: Exception) {
                                    e.printStackTrace()
                                }
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    fun getTrainType(locoType: String, train: String): String? {
        if (train.isEmpty()) {
            return null
        }
        
        val actualTrain = if (locoType == "NA") {
            train
        } else {
            locoType + train
        }
        
        for ((pattern, type) in trainTypePatterns) {
            if (pattern.matcher(actualTrain).matches()) {
                return type
            }
        }
        
        return null
    }
    

}
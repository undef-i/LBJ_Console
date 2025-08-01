package org.noxylva.lbjconsole.model

data class MergeSettings(
    val enabled: Boolean = true,
    val groupBy: GroupBy = GroupBy.TRAIN_AND_LOCO,
    val timeWindow: TimeWindow = TimeWindow.UNLIMITED
)

enum class GroupBy(val displayName: String) {
    TRAIN_ONLY("车次号"),
    LOCO_ONLY("机车号"),
    TRAIN_OR_LOCO("车次号或机车号"),
    TRAIN_AND_LOCO("车次号与机车号")
}

enum class TimeWindow(val displayName: String, val seconds: Long?) {
    ONE_HOUR("1小时", 3600),
    TWO_HOURS("2小时", 7200),
    SIX_HOURS("6小时", 21600),
    TWELVE_HOURS("12小时", 43200),
    ONE_DAY("24小时", 86400),
    UNLIMITED("不限时间", null)
}

fun generateGroupKey(record: TrainRecord, groupBy: GroupBy): String? {
    return when (groupBy) {
        GroupBy.TRAIN_ONLY -> {
            val train = record.train.trim()
            if (train.isNotEmpty() && train != "<NUL>") train else null
        }
        GroupBy.LOCO_ONLY -> {
            val loco = record.loco.trim()
            if (loco.isNotEmpty() && loco != "<NUL>") loco else null
        }
        GroupBy.TRAIN_OR_LOCO -> {
            val train = record.train.trim()
            val loco = record.loco.trim()
            when {
                train.isNotEmpty() && train != "<NUL>" -> train
                loco.isNotEmpty() && loco != "<NUL>" -> loco
                else -> null
            }
        }
        GroupBy.TRAIN_AND_LOCO -> {
            val train = record.train.trim()
            val loco = record.loco.trim()
            if (train.isNotEmpty() && train != "<NUL>" && 
                loco.isNotEmpty() && loco != "<NUL>") {
                "${train}_${loco}"
            } else null
        }
    }
}
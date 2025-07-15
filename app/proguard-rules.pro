-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

-keep class org.json.** { *; }
-keep class org.osmdroid.** { *; }
-keep class org.mapsforge.** { *; }

-keepclassmembers class * {
    @androidx.compose.runtime.Composable <methods>;
}

-keep class androidx.compose.** { *; }
-keep class kotlin.** { *; }

-dontwarn org.osmdroid.**
-dontwarn org.mapsforge.**
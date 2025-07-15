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

-keep class org.xmlpull.** { *; }
-keep class org.kxml2.** { *; }
-keep class android.content.res.XmlResourceParser { *; }

-dontwarn org.osmdroid.**
-dontwarn org.mapsforge.**
-dontwarn org.xmlpull.**
-dontwarn org.kxml2.**
# TourBot ProGuard Rules
# Add any project specific keep rules here:

# Keep annotations
-keepattributes *Annotation*

# Kotlinx Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.opendroids.tourbot.**$$serializer { *; }
-keepclassmembers class com.opendroids.tourbot.** {
    *** Companion;
}
-keepclasseswithmembers class com.opendroids.tourbot.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Keep all model classes used for serialization
-keep class com.opendroids.tourbot.data.remote.model.** { *; }
-keep class com.opendroids.tourbot.data.model.** { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Hilt
-keep class dagger.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ComponentSupplier { *; }
-keep class * implements dagger.hilt.internal.GeneratedComponent { *; }
-keepnames @dagger.hilt.android.lifecycle.HiltViewModel class * extends androidx.lifecycle.ViewModel

# Compose
-keep class androidx.compose.** { *; }
-dontwarn androidx.compose.**

# DataStore
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}

# Keep the Application class
-keep class com.opendroids.tourbot.TourBotApp { *; }

# Keep MainActivity
-keep class com.opendroids.tourbot.MainActivity { *; }

# Robot Relay ProGuard Rules

# Keep Gson classes
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class com.utilitron.robotrelay.protocol.** { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**

# NanoHTTPD
-keep class fi.iki.elonen.** { *; }

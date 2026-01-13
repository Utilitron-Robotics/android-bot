# Robot Relay ProGuard Rules

# ============================================
# Core App Classes - Keep all relay classes
# ============================================
-keep class com.utilitron.robotrelay.** { *; }
-keepclassmembers class com.utilitron.robotrelay.** { *; }

# ============================================
# gRPC / Protobuf - Critical for WAN communication
# ============================================
-keep class io.grpc.** { *; }
-keep class com.google.protobuf.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { *; }

# gRPC reflection and service binding
-keep class * extends io.grpc.BindableService { *; }
-keep class * extends io.grpc.ServerServiceDefinition { *; }

# gRPC Netty transport (shaded) - REQUIRED for server to work
-keep class io.grpc.netty.** { *; }
-dontwarn io.grpc.netty.**

# Shaded Netty classes (relocated by grpc-netty-shaded)
-keep class io.grpc.netty.shaded.** { *; }
-dontwarn io.grpc.netty.shaded.**

# Keep gRPC generated code
-keep class ** extends io.grpc.stub.AbstractStub { *; }
-keep class **Grpc { *; }
-keep class **Grpc$* { *; }

# ============================================
# Gson / JSON Serialization
# ============================================
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class com.utilitron.robotrelay.protocol.** { *; }

# Prevent R8 from stripping interface annotations
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault

# ============================================
# OkHttp / Networking
# ============================================
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# ============================================
# NanoHTTPD - HTTP Server
# ============================================
-keep class fi.iki.elonen.** { *; }

# ============================================
# Kotlin Coroutines
# ============================================
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}

# ============================================
# Android Services / Broadcast Receivers
# ============================================
-keep class * extends android.app.Service
-keep class * extends android.content.BroadcastReceiver

# ============================================
# Reflection for JSON parsing
# ============================================
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ============================================
# WebSocket / Java-WebSocket
# ============================================
-keep class org.java_websocket.** { *; }
-dontwarn org.java_websocket.**

# ============================================
# AWS SDK (if using IoT)
# ============================================
-keep class com.amazonaws.** { *; }
-dontwarn com.amazonaws.**

# ============================================
# TTS / Media
# ============================================
-keep class android.speech.tts.** { *; }
-keep class android.media.** { *; }

# ============================================
# Debugging - Keep line numbers for crash reports
# ============================================
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ============================================================
# Flutter — regole ProGuard/R8 per Invisible
# ============================================================

# Flutter engine: non toccare nulla di flutter/io
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Flutter plugin registry
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.app.** { *; }

# Dart VM entry points (evita che R8 rimuova entry points richiamati da Dart)
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# ============================================================
# Kotlin / Coroutines
# ============================================================
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-keepclassmembernames class kotlinx.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**

# ============================================================
# WebRTC (flutter_webrtc)
# ============================================================
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# ============================================================
# WireGuard (wireguard_flutter)
# ============================================================
-keep class com.bevis.wireguard.** { *; }
-keep class com.wireguard.** { *; }
-dontwarn com.wireguard.**

# ============================================================
# SQLCipher (flutter_sqlcipher / sqflite_sqlcipher)
# ============================================================
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }
-dontwarn net.sqlcipher.**

# ============================================================
# Serializzazione JSON — mantieni classi Dart/JNI bridge
# ============================================================
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ============================================================
# JNI / Native code
# ============================================================
-keepclasseswithmembernames class * {
    native <methods>;
}

# ============================================================
# Rimuovi log di debug in release
# ============================================================
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# ============================================================
# Shared Preferences / Android
# ============================================================
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# ============================================================
# Ottimizzazioni aggressive: non toccare enum
# ============================================================
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ============================================================
# Evita errori con reflection su Parcelable
# ============================================================
-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}

# ============================================================
# Invisible — package principale (non offuscare classi JNI-bridge)
# ============================================================
-keep class com.invisible.invisible.** { *; }

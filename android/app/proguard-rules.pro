# Flutter-specific ProGuard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep audio_service classes
-keep class com.ryanheise.audioservice.** { *; }

# Keep just_audio classes
-keep class com.google.android.exoplayer2.** { *; }

# Keep Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }

# Keep on_audio_query
-keep class com.lucasjosino.on_audio_query.** { *; }

# General Android rules
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-dontwarn com.google.android.play.core.**


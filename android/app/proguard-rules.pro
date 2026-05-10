# R8/ProGuard rules for LectureVault
# Suppress warnings for missing Google Play Core classes

-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**

# Keep Flutter classes
-keep class io.flutter.** { *; }
-keep class com.google.protobuf.** { *; }

# Keep ONNX Runtime
-keep class ai.onnxruntime.** { *; }

# Keep Whisper
-keep class com.whisper.** { *; }

# Keep Google Sign In
-keep class com.google.** { *; }
-keep class androidx.** { *; }
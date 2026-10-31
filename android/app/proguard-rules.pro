# Picked up by Flutter's Gradle plugin by name; nothing in
# build.gradle.kts has to point at it.

# flutter_local_notifications keeps every scheduled reminder as JSON
# through Gson, and reads it back with `new TypeToken<ArrayList<
# NotificationDetails>>() {}`. R8's full mode strips the generic
# signature off that anonymous subclass, and Gson then throws
# "Missing type parameter" out of TypeToken.getSuperclassTypeParameter
# — the crash Play showed on release 14, hit the moment a reminder is
# saved or re-scheduled after a reboot. The plugin ships no consumer
# rules of its own; its README says to add Gson's here.
#
# The rules are Gson's own, from
# gson/examples/android-proguard-example/proguard.cfg.
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-if class *
-keepclasseswithmembers,allowobfuscation,allowoptimization class <1> {
  <init>();
}

# The plugin's own model classes are serialised by field name, so the
# names have to survive. This is the rule the plugin's example app uses.
-keep class com.dexterous.** { *; }

# MainActivity.preloadFfmpeg loads this class by name on a thread of its
# own while the engine starts. Kept by name only, so the lookup finds it.
-keepnames class com.antonkarpenko.ffmpegkit.FFmpegKitConfig

# ONNX Runtime (AyahReel Listen, ListenBridge.kt) reaches its Java
# classes from native code by name: R8 must leave them as they are.
-keep class ai.onnxruntime.** { *; }

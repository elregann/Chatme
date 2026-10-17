# flutter_local_notifications reads its cached data with Gson, which needs
# generic type info that R8 would otherwise strip in release builds.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
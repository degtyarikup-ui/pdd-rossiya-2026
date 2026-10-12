# The Godot engine (android/godot/godot-lib.aar) is called from its native library by the original
# class and method names (JNI). Without these rules R8 renames them in a release build and the
# game activity crashes on start: NoSuchMethodError GodotNativeBridge.getRenderView.
-keep class org.godotengine.** { *; }
-keepclassmembers class org.godotengine.** { *; }
-dontwarn org.godotengine.**

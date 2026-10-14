# The Godot engine (android/godot/godot-lib.aar) is called from its native library by the original
# class and method names (JNI). Without these rules R8 renames them in a release build and the
# game activity crashes on start: NoSuchMethodError GodotNativeBridge.getRenderView.
-keep class org.godotengine.** { *; }
-keepclassmembers class org.godotengine.** { *; }
-dontwarn org.godotengine.**

# App plugins expose these methods only to GDScript through runtime reflection.
# Keep the annotations and original method names in release APKs too.
-keepattributes RuntimeVisibleAnnotations
-keepclassmembers class ru.pdd.pdd_app.game.PddHostPlugin {
    @org.godotengine.godot.plugin.UsedByGodot <methods>;
}

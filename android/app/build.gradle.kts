import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "ru.pdd.pdd_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Требуется flutter_local_notifications (backport java.time и пр.).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // Суффикс для тестовой сборки на своё устройство:
    //   flutter build apk --flavor ru --release -Pdev
    // Приложение встаёт РЯДОМ с магазинным, а не поверх: версия из Google Play
    // подписана ключом Google (Play App Signing), локальная — upload-ключом,
    // и Android считает их разными приложениями. Без суффикса установка
    // возможна только после удаления магазинной, вместе со всем прогрессом.
    // На обычные сборки (без -Pdev) не влияет никак.
    val devSuffix = if (project.hasProperty("dev")) ".dev" else ""
    val gitCommit = try {
        val stdout = ByteArrayOutputStream()
        project.exec {
            commandLine("git", "rev-parse", "--short", "HEAD")
            standardOutput = stdout
        }
        stdout.toString().trim()
    } catch (_: Exception) {
        ""
    }

    defaultConfig {
        applicationId = "ru.pdd.pdd_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        applicationIdSuffix = devSuffix
    }

    // Один flavor `ru`: команды сборки и CI собирают с --flavor ru.
    // Сборка: flutter build appbundle --flavor ru --dart-define=COUNTRY=ru
    flavorDimensions += "country"
    productFlavors {
        create("ru") {
            dimension = "country"
            applicationId = "ru.pdd.pdd_app"
            resValue("string", "app_name", if (devSuffix.isNotEmpty()) "ПДД Россия · Тест" else "ПДД Россия 2026")
            resValue("string", "git_commit", if (devSuffix.isNotEmpty()) gitCommit else "")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Dev-only diagnostics: adb run-as can retrieve the game log after a crash.
            isDebuggable = project.hasProperty("dev")
            // The Godot engine's classes are called by name from native code: see proguard-godot.pro.
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-godot.pro")
            // Never silently sign a store release with the debug key.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else if (project.hasProperty("dev")) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

// The 3D game on Godot (game_godot/): engine and exported files are prepared by
// scripts/godot_android_assets.sh into android/godot/ (not in git). Without them
// the app builds as before and the game tab keeps the WebView game.
val godotDir = rootProject.file("godot")
val godotEngine = File(godotDir, "godot-lib.aar")
if (godotEngine.exists()) {
    android {
        sourceSets.getByName("main").assets.srcDir(File(godotDir, "assets"))
        // The game screen's classes need the engine: compiled only with it (src/godot/).
        sourceSets.getByName("main").java.srcDir("src/godot/kotlin")
        // Godot's project files include hidden ones (.godot/): the default pattern drops them.
        androidResources.ignoreAssetsPattern = "!.svn:!.git:!.gitignore:!.ds_store:!*.scc:!CVS:!thumbs.db:!picasa.ini:!*~"
        packaging.jniLibs.pickFirsts += "**/libc++_shared.so"
        // The engine only for 64-bit ARM (every phone the game is tested on, ~75 MB per
        // architecture): elsewhere the bridge reports it missing and the WebView game stays.
        packaging.jniLibs.excludes += listOf("lib/armeabi-v7a/libgodot_android.so", "lib/x86/libgodot_android.so", "lib/x86_64/libgodot_android.so")
        // Game assets are read in place (memory-mapped by Godot), not unpacked.
        androidResources.noCompress += listOf("pck", "sparsepck", "scn", "res", "ctex", "glb")
    }
    dependencies {
        implementation(files(godotEngine))
        implementation("androidx.fragment:fragment:1.8.6")
        implementation("androidx.core:core-splashscreen:1.0.1")
        implementation("androidx.documentfile:documentfile:1.1.0")
    }
}

dependencies {
    implementation("com.google.android.play:app-update:2.1.0")
    implementation("com.android.installreferrer:installreferrer:2.2")
    // Core library desugaring для flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

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

    defaultConfig {
        applicationId = "ru.pdd.pdd_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        applicationIdSuffix = devSuffix
    }

    // Страны: одно приложение на страну, один общий код.
    // Сборка: flutter build appbundle --flavor ru --dart-define=COUNTRY=ru
    flavorDimensions += "country"
    productFlavors {
        create("ru") {
            dimension = "country"
            applicationId = "ru.pdd.pdd_app"
            resValue("string", "app_name", "ПДД Россия 2026")
        }
        create("by") {
            dimension = "country"
            applicationId = "by.pdd.pdd_app"
            resValue("string", "app_name", "ПДД Беларусь 2026")
        }
        create("rs") {
            dimension = "country"
            applicationId = "rs.pdd.pdd_app"
            resValue("string", "app_name", "Auto testovi Srbija 2026")
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
            signingConfig =
                if (keystorePropertiesFile.exists()) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring для flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

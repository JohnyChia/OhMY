import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Navigation SDK bundles the Google Maps Android classes. Keep the existing
// google_maps_flutter discovery UI, but do not package its duplicate native
// play-services-maps artifact alongside Navigation SDK.
configurations.configureEach {
    exclude(group = "com.google.android.gms", module = "play-services-maps")
}

android {
    namespace = "com.example.flutter_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.flutter_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Google Navigation SDK for Flutter requires Android API 24 or newer.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val localProperties = Properties()
        val localPropertiesFile = rootProject.file("local.properties")
        if (localPropertiesFile.exists()) {
            localProperties.load(FileInputStream(localPropertiesFile))
        }
        fun configuredMapsKey(value: String?): String? {
            val candidate = value?.trim().orEmpty()
            if (candidate.isEmpty() ||
                Regex("^(YOUR_|REPLACE|replace-with)", RegexOption.IGNORE_CASE)
                    .containsMatchIn(candidate)) {
                return null
            }
            return candidate
        }
        val mapsApiKey =
            configuredMapsKey(localProperties.getProperty("MAPS_API_KEY"))
                ?: configuredMapsKey(System.getenv("MAPS_API_KEY"))
                ?: throw GradleException(
                    "A real MAPS_API_KEY is required in android/local.properties or the build environment."
                )
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Reuse the audited openWakeWord preprocessing assets from the bundled
    // Android library example. The trained Nova classifier remains an app
    // asset so release builds cannot silently substitute another wake phrase.
    sourceSets.getByName("main").assets.srcDir(
        "../third_party/openwakeword-android-kt/app/src/main/assets"
    )
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")
}

flutter {
    source = "../.."
}

dependencies {
    implementation(project(":openwakeword"))
}

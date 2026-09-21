import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

base {
    // Names the .aab and the intermediate artefacts. It does NOT name what
    // `flutter build apk` drops in build/app/outputs/flutter-apk — the Flutter
    // Gradle plugin writes those itself, and tool/release.sh is what renames
    // them on the way into releases/.
    archivesName.set("penny")
}

// Release signing, when there is a key to sign with.
//
// android/key.properties is gitignored, because the keystore password lives in
// it, so a fresh clone has no key and falls back to the debug one rather than
// failing the build. FEATURES.md carries the keytool line that makes one.
val signing = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.ayroid.penny"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ayroid.penny"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signing.isNotEmpty()) {
            create("release") {
                storeFile = rootProject.file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The debug key is the fallback, not the plan: it keeps
            // `flutter run --release` working on a clone with no key.properties,
            // and tool/release.sh refuses to build releases/ without a real one.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // The themes in res/values*/styles.xml. local_auth's biometric prompt
    // crashes on Android 8 and below under a non-AppCompat theme.
    implementation("androidx.appcompat:appcompat:1.7.1")
}

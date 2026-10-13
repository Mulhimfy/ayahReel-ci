import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The build number lives in build_number.txt at the repo root and is bumped by
// tool/build-number.sh (or .ps1). Both stores require it to be strictly greater
// than the last accepted upload — Apple rejects a duplicate CFBundleVersion,
// Play a duplicate versionCode.
//
// Gradle only READS the file; it never bumps it. Bumping happens once per build
// command, in the script:
//
//   flutter build appbundle --build-number=$(tool/build-number.sh)
//
// That flag is the path that matters, because it is the ONLY way iOS gets the
// number too (CFBundleVersion comes from FLUTTER_BUILD_NUMBER, which Gradle
// cannot reach). Reading the file here is just a fallback so a bare
// `flutter build apk` or an Android Studio run still gets a sane versionCode
// instead of a stale pubspec value.
//
// maxOf means an explicit --build-number always wins, since the script's value
// is written to the file before Gradle reads it.
val buildNumberFile = rootProject.file("../build_number.txt")
val storedBuildNumber = runCatching {
    buildNumberFile.readText().filter { it.isDigit() }.toInt()
}.getOrDefault(0)

val autoVersionCode = maxOf(storedBuildNumber, flutter.versionCode)

// Release signing lives in android/key.properties, which is gitignored.
// See android/key.properties.example for the expected keys.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.ayahreel.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on older Android
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Never change this after the first Play release: Shorebird ties every
        // release and patch to the installed app's identity.
        applicationId = "com.ayahreel.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ffmpeg-kit requires 24+
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = autoVersionCode
        versionName = flutter.versionName
        // Printed so you can read off the exact string Shorebird will need:
        //   shorebird patch android --release-version <versionName>+<versionCode>
        println("AyahReel version: ${flutter.versionName}+$autoVersionCode")
    }

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Falls back to debug keys so `flutter run --release` still works
            // locally. Anything shipped to Play or patched by Shorebird must be
            // signed with the real keystore, and with the SAME key every time.
            signingConfig = signingConfigs.getByName(if (hasKeystore) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

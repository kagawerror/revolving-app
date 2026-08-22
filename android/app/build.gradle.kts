import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release signing is loaded from android/key.properties (gitignored). When the
// file is absent (e.g. a fresh clone or CI without secrets), release builds will
// fail at signing — that is intentional: a release APK must be signed with the
// real upload key so self-hosted updates verify against a stable signature.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "ph.com.brigada.revapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by the ota_update plugin (in-app self-update).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ph.com.brigada.revapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // R8 is DISABLED for release. Flutter's Gradle plugin enables
            // minification + resource shrinking by default (isMinifyEnabled=true
            // with proguard-android-optimize.txt), and AGP 8's R8 "full mode"
            // optimization corrupts reflection-based libraries. Concretely it
            // mangled WorkManager's Room reflection (WorkManager is pulled in by
            // the ota_update plugin), crashing the app at launch with "Failed to
            // create an instance of class androidx.work.impl.WorkDatabase" — the
            // app installed and showed its icon but would not open. This app
            // ships internally (APK size is dominated by native libs, which
            // shrinking can't touch) and leans on several reflection-heavy
            // plugins (Firebase, OneSignal, WorkManager, image_cropper), so
            // shrinking is more risk than benefit. These lines run AFTER the
            // Flutter plugin's apply(), so they override its defaults.
            isMinifyEnabled = false
            isShrinkResources = false
            // Sign with the release upload key (android/key.properties).
            signingConfig = signingConfigs.getByName("release")
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
  // Required by the ota_update plugin for core library desugaring.
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

  // Import the Firebase BoM
  implementation(platform("com.google.firebase:firebase-bom:34.14.0"))


  // TODO: Add the dependencies for Firebase products you want to use
  // When using the BoM, don't specify versions in Firebase dependencies
  implementation("com.google.firebase:firebase-analytics")


  // Add the dependencies for any other desired Firebase products
  // https://firebase.google.com/docs/android/setup#available-libraries
}

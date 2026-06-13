import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release signing config. Secrets live in android/key.properties (gitignored),
// which points at a keystore stored OUTSIDE the repo. Absent the file (e.g. CI
// without secrets), the release build falls back to debug signing below.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.rev_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by the ota_update plugin (uses java.time / WorkManager APIs).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent distribution identity — Android matches self-hosted updates by
        // applicationId, so this must never change once released. Registered in the
        // Firebase project (see google-services.json). namespace stays com.example.rev_app
        // (independent of applicationId; changing it would require moving MainActivity).
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
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String).let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
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
            // create an instance of class androidx.work.impl.WorkDatabase". This
            // app ships internally (APK size is dominated by native libs, which
            // shrinking can't touch) and leans on several reflection-heavy
            // plugins (Firebase, OneSignal, WorkManager, image_cropper), so
            // shrinking is more risk than benefit. These lines run AFTER the
            // Flutter plugin's apply(), so they override its defaults.
            isMinifyEnabled = false
            isShrinkResources = false
            // Sign with the release keystore when key.properties is present;
            // otherwise fall back to debug so `flutter run --release` still works
            // on machines without the signing secrets.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
  // Core library desugaring runtime, required by the ota_update plugin.
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

  // Import the Firebase BoM
  implementation(platform("com.google.firebase:firebase-bom:34.14.0"))


  // TODO: Add the dependencies for Firebase products you want to use
  // When using the BoM, don't specify versions in Firebase dependencies
  implementation("com.google.firebase:firebase-analytics")


  // Add the dependencies for any other desired Firebase products
  // https://firebase.google.com/docs/android/setup#available-libraries
}

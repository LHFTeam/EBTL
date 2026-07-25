import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase config is a secret and is never committed. Materialize
// android/app/google-services.json before the Google Services plugin needs it,
// preferring (1) an existing file, then (2) the GOOGLE_SERVICES_JSON_BASE64 env
// var (for CI/release), then (3) a copy from the app root (customer-app/).
val googleServicesJson = file("google-services.json")
if (!googleServicesJson.exists()) {
    val base64Config = System.getenv("GOOGLE_SERVICES_JSON_BASE64")
    val appRootCopy = rootProject.file("../google-services.json")
    if (!base64Config.isNullOrBlank()) {
        googleServicesJson.writeBytes(Base64.getDecoder().decode(base64Config.trim()))
    } else if (appRootCopy.exists()) {
        appRootCopy.copyTo(googleServicesJson, overwrite = true)
    }
}

// Apply Firebase's Google Services plugin only when config is present, so the
// app still builds for contributors without Firebase credentials (push is then
// simply disabled at runtime; see PushNotificationService).
if (googleServicesJson.exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Release signing. The upload keystore is a secret and is never committed
// (see android/.gitignore). Supply it in one of two ways:
//
//  1. Local file  — create android/key.properties (see key.properties.example)
//     with storeFile/storePassword/keyAlias/keyPassword.
//  2. CI env vars — for automated release builds, set:
//        ANDROID_KEYSTORE_BASE64    base64 of the .jks file
//        ANDROID_KEYSTORE_PASSWORD  keystore (store) password
//        ANDROID_KEY_ALIAS          key alias
//        ANDROID_KEY_PASSWORD       key password
//
// When neither is present, release builds fall back to debug signing so
// `flutter run --release` and the CI debug build still work without secrets.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
var hasReleaseSigning = false

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    hasReleaseSigning = true
} else {
    val keystoreBase64 = System.getenv("ANDROID_KEYSTORE_BASE64")
    val storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
    val keyAlias = System.getenv("ANDROID_KEY_ALIAS")
    val keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
    if (!keystoreBase64.isNullOrBlank() &&
        !storePassword.isNullOrBlank() &&
        !keyAlias.isNullOrBlank() &&
        !keyPassword.isNullOrBlank()
    ) {
        val keystoreFile = file("upload-keystore.jks")
        keystoreFile.writeBytes(Base64.getDecoder().decode(keystoreBase64.trim()))
        keystoreProperties.setProperty("storeFile", keystoreFile.absolutePath)
        keystoreProperties.setProperty("storePassword", storePassword)
        keystoreProperties.setProperty("keyAlias", keyAlias)
        keystoreProperties.setProperty("keyPassword", keyPassword)
        hasReleaseSigning = true
    }
}

android {
    namespace = "wtf.ebtl.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "wtf.ebtl.app"
        // Firebase requires Android API 23+; flutter_stripe requires 21+.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Sign with the real upload key when configured, otherwise fall back
            // to the debug key so `flutter run --release` and CI debug builds
            // still work without the secret keystore.
            signingConfig = if (hasReleaseSigning) {
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

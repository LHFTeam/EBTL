import java.util.Base64

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

android {
    namespace = "wtf.ebtl.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "wtf.ebtl.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Firebase requires Android API 23+; flutter_stripe requires 21+.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

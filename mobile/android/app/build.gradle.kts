plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key comes from CI secrets when they are set (see README.md);
// otherwise the shared key in android/keystore/ is used. It is the same key
// the first (WebView) APK was signed with, so this app installs over it.
val env: Map<String, String> = System.getenv()
fun secret(name: String, fallback: String) = env[name]?.takeIf { it.isNotEmpty() } ?: fallback

android {
    namespace = "studio.stemik.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs java.time on older Android.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "studio.stemik.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = file(secret("STEMIK_KEYSTORE", "../keystore/stemik-shared.jks"))
            storePassword = secret("STEMIK_KEYSTORE_PASSWORD", "stemik-shared")
            keyAlias = secret("STEMIK_KEY_ALIAS", "stemik")
            keyPassword = secret("STEMIK_KEY_PASSWORD", "stemik-shared")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

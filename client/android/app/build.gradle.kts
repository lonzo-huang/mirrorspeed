import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Load signing config from android/key.properties ──────────────────────────
val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties().apply {
    if (keyPropsFile.exists()) load(FileInputStream(keyPropsFile))
}

android {
    namespace = "com.mirrorspeed.mirrorspeed_vpn"   // shared namespace for R class
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "env"

    productFlavors {
        create("global") {
            dimension    = "env"
            applicationId = "com.mirrorspeed.mirrorspeed_vpn"
            resValue("string", "app_name", "MirrorSpeed VPN")
            manifestPlaceholders["deepLinkScheme"] = "mirrorspeed"
        }
        create("cn") {
            dimension    = "env"
            applicationId = "com.mirrorspeed.jinsu"
            resValue("string", "app_name", "镜速加速器")
            manifestPlaceholders["deepLinkScheme"] = "jinsuapp"
        }
    }

    signingConfigs {
        create("release") {
            storeFile     = keyProps["storeFile"]?.let { file(it as String) }
            storePassword = keyProps["storePassword"] as String?
            keyAlias      = keyProps["keyAlias"]      as String?
            keyPassword   = keyProps["keyPassword"]   as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled   = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

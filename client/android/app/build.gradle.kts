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
        // 单一安装包（已合并原 global/cn 两个 flavor）。Google Play 用此 id 上架。
        applicationId = "com.mirrorspeed.vpn"
        // AdMob (google_mobile_ads) 要求 minSdk >= 23；取两者较大值。
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // OAuth 深链 scheme（单一）。app_name 由 res/values(-zh) 按语言自动切换。
        manifestPlaceholders["deepLinkScheme"] = "mirrorspeed"
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


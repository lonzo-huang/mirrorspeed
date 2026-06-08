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

        // 直接下载的 APK 用 abiFilters 真正只保留指定架构（连第三方 jniLibs 也裁掉），
        // 避免「某架构完整、其它架构残缺」的畸形包导致部分手机「解析失败」。
        // 由 release.ps1 通过环境变量 MS_TARGET_ABI 注入；Play 的 .aab 不设此变量，
        // 保留全部架构由 Play 按设备分发。
        System.getenv("MS_TARGET_ABI")?.takeIf { it.isNotBlank() }?.let { abi ->
            ndk { abiFilters.addAll(abi.split(",").map { it.trim() }) }
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


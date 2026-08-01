import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------
// 读取签名信息（android/key.properties，由 CI 在构建前自动生成，
// 内容指向 CI 解码出来的 release.jks）。
// 本地开发如果没有这个文件也没关系，release 签名会退回 debug 签名，
// 只影响本地调试，不影响 CI 云端打包。
// ---------------------------------------------------------------------
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // 必须和 flutter create --org com.zhaohongli --project-name unraid_mobile
    // 实际生成的 Kotlin 包路径完全一致：android/app/src/main/kotlin/com/zhaohongli/unraid_mobile/MainActivity.kt
    // 之前这里少了下划线（写成 unraidmobile），会导致系统按 AndroidManifest
    // 里的 ".MainActivity" 找不到真正的类，启动时立刻崩溃、连界面都进不去。
    namespace = "com.zhaohongli.unraid_mobile"
    compileSdk = flutter.compileSdkVersion
    // 显式指定为插件里要求的最高 NDK 版本（package_info_plus /
    // shared_preferences_android / url_launcher_android 等都要求 27.x），
    // 不能用 flutter.ndkVersion 的默认值，否则会因为版本不一致构建失败。
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // 应用唯一包名：必须和上面的 namespace 保持一致，永远不要改动，
        // 否则手机会把新版本当成"另一个 App"，无法实现原地升级安装。
        applicationId = "com.zhaohongli.unraid_mobile"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        // versionCode / versionName 由 CI 通过
        // `flutter build apk --build-name=... --build-number=...` 传入，
        // 这里读取 flutter 注入的默认值即可。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasKeystore) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 有签名信息就用正式签名（CI 环境）；本地没配置时退回 debug 签名，
            // 保证本地也能跑 `flutter build apk` 做测试。
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {}

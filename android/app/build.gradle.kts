plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.onyxvpn.onyx_vpn"
    compileSdk = 35
    // ✅ إصلاح ١: رفعنا NDK لـ 28 — يحل مشكلة shared_preferences وunity_ads وباقي المكتبات
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.onyxvpn.onyx_vpn"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    signingConfigs {
        create("release") {
            keyAlias = "upload"
            keyPassword = "nemo112233"
            storeFile = file("upload-keystore.jks")
            storePassword = "nemo112233"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // ✅ إصلاح ٢: حل تعارض libgojni.so بين openvpn و v2ray
    packaging {
        jniLibs {
            pickFirsts += setOf(
                "**/libgojni.so",
                "**/libc++_shared.so"
            )
        }
    }
}

flutter {
    source = "../.."
}

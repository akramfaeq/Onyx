plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.onyxvpn.onyx_vpn"
    compileSdk = 35
    ndkVersion = "25.1.8937393"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.onyxvpn.onyx_vpn"
        minSdk = 21
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        ndk {
            abiFilters += listOf("arm64-v8a")
        }
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

    // ─── مهم جداً: منع ضغط الملفات الكبيرة ──────────────────
    // "" = ملفات بدون امتداد (xray, tun2socks)
    androidResources {
        noCompress += listOf("", "dat", "so", "bin")
    }

    // منع Flutter من ضغط assets
    aaptOptions {
        noCompress("", "dat", "so", "bin")
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.core:core:1.13.1")
}

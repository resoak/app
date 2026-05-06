plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.lecture_vault"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.example.lecture_vault"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        androidResources {
            noCompress += listOf("bin")
        }
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        jniLibs {
            // 這是解決 FFmpeg 加載失敗的關鍵：保留所有架構的原生庫
            useLegacyPackaging = true
            pickFirsts.add("**/libffmpegkit.so")
            pickFirsts.add("**/libavcodec.so")
            pickFirsts.add("**/libavformat.so")
            pickFirsts.add("**/libavutil.so")
            pickFirsts.add("**/libswresample.so")
            pickFirsts.add("**/libswscale.so")
        }
    }
}

flutter {
    source = "../.."
}

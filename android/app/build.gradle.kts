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

    // 移除之前的 pickFirst，讓單一插件自行運作
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    buildTypes {
        getByName("debug") {
            // 本機常見 x86_64 AVD；實機為 arm64-v8a。兩者都打包，方便 flutter run。
            ndk {
                abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
            }
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
            // 上架／實機發佈：只留 ARM64，APK 較小。
            ndk {
                abiFilters.add("arm64-v8a")
            }
        }
    }
}

flutter {
    source = "../.."
}
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
        // 提升到 Java 11 以解決過時警告
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    sourceSets {
        getByName("main") {
            // 指定手動放入 .so 檔的目錄
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    defaultConfig {
        applicationId = "com.example.lecture_vault"
        // S24 與 sherpa-onnx 建議至少 24
        minSdk = 24 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 強制指定 S24 (SM-S9210) 的 64 位元架構
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    // 解決 mergeDebugNativeLibs 衝突的核心區塊
    packaging {
        resources {
            // 當多個套件 (onnxruntime vs sherpa) 都有同名檔案時，優先使用第一個找到的
            pickFirst("lib/armeabi-v7a/libonnxruntime.so")
            pickFirst("lib/arm64-v8a/libonnxruntime.so")
            pickFirst("lib/x86_64/libonnxruntime.so")
            pickFirst("lib/x86/libonnxruntime.so")
            
            // 針對 sherpa 的 C API 檔案也做同樣處理，防止潛在衝突
            pickFirst("lib/arm64-v8a/libsherpa-onnx-c-api.so")
            pickFirst("lib/armeabi-v7a/libsherpa-onnx-c-api.so")
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 這裡通常會由 Flutter 自動管理
}
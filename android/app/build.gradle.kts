plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sivaeee005.ac_controller"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.sivaeee005.ac_controller"
        // The Matter SDK (connectedhomeip) Android libraries require API 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // Matter SDK native libraries are built for these ABIs in CI.
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    sourceSets {
        getByName("main") {
            // Filled by CI from the Matter SDK build (see .github/workflows/build.yml).
            jniLibs.srcDirs("libs/jniLibs")
            assets.srcDirs("src/main/assets", "build-assets")
        }
    }

    buildTypes {
        release {
            // Personal-use build, signed with the debug key. Do not publish.
            signingConfig = signingConfigs.getByName("debug")
            // The Matter SDK uses JNI and reflection; keep its classes intact.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    // Matter SDK Java libraries (CHIPController.jar etc.), produced in CI.
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("com.google.code.findbugs:jsr305:3.0.2")
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

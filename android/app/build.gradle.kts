import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android") // Explicit Kotlin version
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(keystorePropertiesFile.inputStream())
    } else {
        error("key.properties file not found at ${keystorePropertiesFile.absolutePath}")
    }
}

android {
    namespace = "com.twalitso.padue"
    compileSdk = 35 // Match Flutter’s typical compileSdk
    ndkVersion = flutter.ndkVersion
   // ndkVersion = "29.0.13113456"
  // ndkVersion = "29.0.13113456"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.twalitso.padue"
        minSdk = flutter.minSdkVersion
        targetSdk = 35 // Raise to 33 for Photo Picker without permissions
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        register("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias") ?: error("keyAlias not set in key.properties")
            keyPassword = keystoreProperties.getProperty("keyPassword") ?: error("keyPassword not set in key.properties")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) } ?: error("storeFile not set in key.properties")
            storePassword = keystoreProperties.getProperty("storePassword") ?: error("storePassword not set in key.properties")
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation(platform("com.google.firebase:firebase-bom:34.0.0"))
    implementation("com.google.firebase:firebase-appcheck-playintegrity:17.1.2")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.android.gms:play-services-ads:23.2.0")
    implementation("com.google.android.gms:play-services-location:21.3.0")
    implementation("com.google.firebase:firebase-messaging")
    implementation("androidx.fragment:fragment-ktx:1.6.2") // For compatibility
    implementation("androidx.activity:activity-ktx:1.8.0") 
    implementation("com.onesignal:OneSignal:[4.8.7, 4.99.99]")
}

flutter {
    source = "../.."
}

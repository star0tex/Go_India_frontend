plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.startech.goindia"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.startech.goindia"
        minSdk = 23  // Firebase Auth minimum requirement
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        multiDexEnabled = true
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // For production, create proper signing config
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        
        debug {
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = true
        }
    }
    
    packaging {
        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "/META-INF/DEPENDENCIES"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")  // Changed from 2.0.4
    
    // Firebase BOM (Bill of Materials) - manages versions automatically
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    
    // Firebase Authentication (remove -ktx when using BOM)
    implementation("com.google.firebase:firebase-auth")
    
    // Firebase Analytics (remove -ktx when using BOM)
    implementation("com.google.firebase:firebase-analytics")
    
    // Firebase Messaging (for FCM notifications)
    implementation("com.google.firebase:firebase-messaging")
    
    // Google Play Services Auth (required for phone auth)
    implementation("com.google.android.gms:play-services-auth:21.2.0")
    implementation("com.google.android.gms:play-services-auth-api-phone:18.1.0")
    
    // MultiDex support
    implementation("androidx.multidex:multidex:2.0.1")
}
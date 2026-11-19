import java.util.Properties

// Wear OS companion: a Tile with a mic that sends spoken reminders to the phone app.
// Must share the phone app's applicationId and signing key, or the Data Layer won't connect them.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        load(keystorePropertiesFile.inputStream())
    }
}

// Same version as the phone app (pubspec.yaml "version: 0.7.0+481"). Version codes are
// 200000 + the build number here and 100000 + it for the phone, so both share one Play listing.
val pubspecVersion = rootProject.file("../pubspec.yaml").readLines()
    .first { it.startsWith("version:") }.substringAfter(":").trim()

android {
    namespace = "com.chaplyk.memory.wear"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.chaplyk.memory"
        minSdk = 30
        targetSdk = 36
        versionCode = 200_000 + pubspecVersion.substringAfter("+").toInt()
        versionName = pubspecVersion.substringBefore("+")
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { rootProject.file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
    implementation("androidx.activity:activity-compose:1.10.1")
    // Play services brings an old fragment, too old for the permission request API (lint error).
    implementation("androidx.fragment:fragment:1.8.8")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.2")
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    implementation("androidx.wear.tiles:tiles:1.5.0")
    implementation("androidx.wear.protolayout:protolayout:1.3.0")
    implementation("com.google.guava:guava:33.4.8-android")
}

pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        // Normalize Windows paths to Linux paths if in Docker
        if (System.getenv("DOCKER_CONTAINER") != null || System.getenv("FLUTTER_ROOT") == "/home/flutter/flutter") {
            flutterSdkPath.replace("\\", "/").replace("D:", "/app")
        } else {
            flutterSdkPath
        }
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

// For Docker builds, ensure all file references use normalized paths
gradle.beforeProject {
    if (System.getenv("DOCKER_CONTAINER") != null || System.getenv("FLUTTER_ROOT") == "/home/flutter/flutter") {
        System.setProperty("org.gradle.java.home.use.file.uri", "true")
        System.setProperty("org.gradle.native.file.normalization", "true")
    }
}

include(":app")

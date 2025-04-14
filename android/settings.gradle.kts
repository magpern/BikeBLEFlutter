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
    // Only apply Docker-specific settings when running in Docker
    if (System.getenv("DOCKER_CONTAINER") != null || System.getenv("FLUTTER_ROOT") == "/home/flutter/flutter") {
        System.setProperty("org.gradle.java.home.use.file.uri", "true")
        System.setProperty("org.gradle.native.file.normalization", "true")
    }
}

// Override build directories only when in Docker
if (System.getenv("DOCKER_CONTAINER") != null || System.getenv("FLUTTER_ROOT") == "/home/flutter/flutter") {
    // We need to use a different approach for allprojects in settings.gradle.kts
    gradle.addListener(object : org.gradle.api.execution.TaskExecutionListener {
        override fun beforeExecute(task: org.gradle.api.Task) {
            if (task.project == task.project.rootProject) {
                task.project.buildDir = file("/app/build")
            } else {
                task.project.buildDir = file("/app/build/${task.project.name}")
            }
        }
        
        override fun afterExecute(task: org.gradle.api.Task, state: org.gradle.api.tasks.TaskState) {
            // Do nothing
        }
    })
}

include(":app")

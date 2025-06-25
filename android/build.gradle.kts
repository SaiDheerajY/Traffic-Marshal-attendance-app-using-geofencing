// traff_att_new/android/build.gradle.kts
// This file is for configuring the build environment for all modules.

// This buildscript block is crucial. It defines dependencies (like Android Gradle Plugin)
// that Gradle itself needs to execute the build.
buildscript { // <--- THIS BLOCK IS MISSING IN YOUR SNIPPET
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Android Gradle Plugin (AGP) - essential for Android projects
        classpath("com.android.tools.build:gradle:8.4.1")

        // Kotlin Gradle Plugin - required if you're using Kotlin in your Android modules
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.22") // Adjust this Kotlin version if different

        // Google Services plugin - REQUIRED if you use Firebase or Google Play Services
        classpath("com.google.gms:google-services:4.4.1")
    }
} // <--- AND ITS CLOSING BRACE

// This block defines repositories that apply to all modules in your project
// for their runtime/implementation dependencies.
allprojects {
    repositories {
        google()
        mavenCentral()
        // Add other custom Maven repositories here if you use private libraries
        // maven("https://jitpack.io") // Example for JitPack
    }
}

// Custom build directory configuration:
// This moves the 'build' output directory for the root project (android folder)
// to the parent directory (your Flutter project root's 'build' folder).
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Apply the custom build directory to all subprojects (e.g., 'app' module, plugins)
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// This line ensures that the 'app' module is evaluated before other subprojects.
// While sometimes necessary, for standard Flutter projects, Gradle usually handles
// evaluation order implicitly. You can consider removing this if you encounter
// unexpected build issues, as it can sometimes lead to circular dependencies.
subprojects {
    project.evaluationDependsOn(":app")
}

// This task registers a 'clean' task to delete all build outputs.
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
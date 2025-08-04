// Root-level build.gradle.kts

buildscript {
    dependencies {
        classpath("com.google.gms:google-services:4.3.15")
    }
    repositories {
        google()
        mavenCentral()
    }
}

extra["minSdkVersion"] = 23

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val subprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(subprojectBuildDir)

    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
        options.compilerArgs.add("-Xlint:-options")
        options.compilerArgs.add("-Xlint:deprecation")
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}

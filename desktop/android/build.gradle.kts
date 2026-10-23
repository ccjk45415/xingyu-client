allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
    // This plugin ships 16 KB compatible native libraries but its Java target
    // predates AGP 9's Kotlin default. Keep both compile tasks on Java 17.
    if (project.name == "flutter_avif_android") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension> {
                finalizeDsl {
                    it.compileSdk = 36
                    it.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                    it.compileOptions.targetCompatibility = JavaVersion.VERSION_17
                    // Upstream ships identical Java and Kotlin registrants.
                    // AGP 9 compiles Kotlin automatically; use only that copy.
                    it.sourceSets.getByName("main").java.setSrcDirs(listOf("src/main/kotlin"))
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

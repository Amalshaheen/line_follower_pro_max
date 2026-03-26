import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.Project

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

fun Project.namespaceFromManifestOrFallback(): String {
    val manifestFile = file("src/main/AndroidManifest.xml")
    if (manifestFile.exists()) {
        val packageName =
            Regex("package=\\\"([^\\\"]+)\\\"")
                .find(manifestFile.readText())
                ?.groupValues
                ?.getOrNull(1)
                ?.trim()
        if (!packageName.isNullOrEmpty()) {
            return packageName
        }
    }

    val normalizedName = name.replace('-', '_')
    return "com.example.$normalizedName"
}

subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<ApplicationExtension>("android") {
            if (namespace.isNullOrBlank()) {
                namespace = project.namespaceFromManifestOrFallback()
            }
        }
    }

    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            if (namespace.isNullOrBlank()) {
                namespace = project.namespaceFromManifestOrFallback()
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

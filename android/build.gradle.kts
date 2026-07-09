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
    var manifestPackageName: String? = null
    val manifestFile = file("${project.projectDir}/src/main/AndroidManifest.xml")
    if (manifestFile.exists()) {
        val content = manifestFile.readText()
        val match = Regex("package=\"([^\"]+)\"").find(content)
        if (match != null) {
            manifestPackageName = match.groupValues[1]
            // Strip the package attribute to prevent AGP 8 crash
            val newContent = content.replace(match.value, "")
            manifestFile.writeText(newContent)
        }
    }

    afterEvaluate {
        val android = extensions.findByName("android")
        if (android != null) {
            val hasNamespace = try {
                android.javaClass.getMethod("getNamespace").invoke(android) != null
            } catch (e: Exception) {
                false
            }
            if (!hasNamespace) {
                try {
                    val pkg = manifestPackageName ?: (project.group.toString() + "." + project.name)
                        .replace(Regex("[^a-zA-Z0-9.]"), ".")
                        .toLowerCase()
                    android.javaClass.getMethod("setNamespace", String::class.java).invoke(android, pkg)
                } catch (e: Exception) {}
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

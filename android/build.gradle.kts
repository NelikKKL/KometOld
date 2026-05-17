allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ── Auto-fix: add missing namespace to legacy Android library plugins ─────────
// Needed when a pub dependency ships a build.gradle without `namespace`
// (which is required since AGP 8.0).
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            val cls = androidExt.javaClass
            try {
                val nsMethod = cls.methods.find { it.name == "getNamespace" }
                val ns = nsMethod?.invoke(androidExt) as? String
                if (ns.isNullOrBlank()) {
                    // Fall back to the package attribute from AndroidManifest.xml
                    val manifestFile = file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val pkg = manifestFile.readText()
                            .let { Regex("""package\s*=\s*"([^"]+)"""").find(it) }
                            ?.groupValues?.get(1)
                        if (!pkg.isNullOrBlank()) {
                            cls.methods.find { it.name == "namespace" && it.parameterCount == 1 }
                                ?.invoke(androidExt, pkg)
                        }
                    }
                }
            } catch (_: Exception) { /* ignore — not an Android project */ }
        }
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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

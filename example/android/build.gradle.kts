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
// Every Android plugin module is compiled against the compileSdk it declares,
// and a release build checks that each one meets what its own dependencies
// require. Several plugins in this dependency tree still declare 34 (file_picker
// among them) while flutter_plugin_android_lifecycle requires 36, so without
// this every release build fails before it reaches app code. It only raises
// which Android APIs a module compiles against: minSdk and targetSdk, which
// decide how the app behaves at runtime, are untouched. Registered before the
// evaluationDependsOn block below, so it runs for every plugin module.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        val current = android?.compileSdkVersion?.removePrefix("android-")?.toIntOrNull()
        if (android != null && current != null && current < 36) {
            android.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

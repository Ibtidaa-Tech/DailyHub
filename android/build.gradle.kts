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

// ---------------------------------------------------------------------------
// Keep every Android module on the same compileSdk.
//
// Some Flutter plugins still pin an older compileSdk than the AndroidX
// libraries they pull in require. file_picker, for instance, compiles against
// android-34 while flutter_plugin_android_lifecycle now demands 36, which
// fails the build at :file_picker:checkDebugAarMetadata.
//
// compileSdk only decides which APIs are visible at compile time. It does not
// change runtime behaviour (that's targetSdk) or which devices can install the
// app (that's minSdk), so raising it everywhere is safe.
//
// This block MUST come before the evaluationDependsOn(":app") block below:
// that one forces :app to evaluate immediately, and afterEvaluate cannot be
// registered on a project that has already been evaluated. The state.executed
// check is a second line of defence in case the ordering shifts again.
//
// The property is set reflectively on purpose. The Android Gradle Plugin has
// spelled it several ways across AGP 7/8/9, and a hard reference to the wrong
// one stops this script from compiling at all. If none of the spellings match,
// this logs a warning and leaves the build untouched rather than breaking it.
// ---------------------------------------------------------------------------
val dailyHubCompileSdk = 36

subprojects {
    val raiseCompileSdk = {
        val android = extensions.findByName("android")
        if (android != null) {
            val methods = android.javaClass.methods
            val current = runCatching {
                methods.firstOrNull { it.name == "getCompileSdk" && it.parameterCount == 0 }
                    ?.invoke(android) as? Int
            }.getOrNull()

            if (current == null || current < dailyHubCompileSdk) {
                // name to parameter type, tried in order
                val attempts = listOf(
                    "setCompileSdk" to Integer::class.java,
                    "setCompileSdk" to Int::class.javaPrimitiveType,
                    "compileSdkVersion" to Int::class.javaPrimitiveType,
                    "compileSdkVersion" to String::class.java,
                )
                var applied = false
                for ((setterName, type) in attempts) {
                    if (applied) break
                    val m = methods.firstOrNull {
                        it.name == setterName && it.parameterCount == 1 && it.parameterTypes[0] == type
                    }
                    if (m != null) {
                        val arg: Any =
                            if (type == String::class.java) {
                                "android-$dailyHubCompileSdk"
                            } else {
                                dailyHubCompileSdk
                            }
                        applied = runCatching { m.invoke(android, arg) }.isSuccess
                        if (applied) {
                            logger.info("DailyHub: $setterName -> $dailyHubCompileSdk for ${project.name}")
                        }
                    }
                }
                if (!applied) {
                    logger.warn(
                        "DailyHub: could not raise compileSdk for ${project.name}. If the build " +
                            "fails on checkDebugAarMetadata, set it to $dailyHubCompileSdk by hand."
                    )
                }
            }
        }
    }

    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

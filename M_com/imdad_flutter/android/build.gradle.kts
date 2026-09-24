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
// بعض الإضافات (file_picker و printing على 34، و jni و sqlite3_flutter_libs على 35) ما زالت
// تُعلن compileSdk أقدم مما يشترطه flutter_plugin_android_lifecycle (36 فأعلى)، فيفشل
// `checkReleaseAarMetadata`. نرفعها كلها هنا بدل تثبيت نسخ أقدم من الإضافات.
// الضبط بالانعكاس لأن نوع امتداد `android` يتغيّر بين إصدارات AGP (هنا 9.1.0)، ويجب أن
// يسبق `evaluationDependsOn` أدناه لأنه يقيّم المشاريع فورًا فيغلق باب `afterEvaluate`.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        val getter = android.javaClass.methods.firstOrNull { it.name == "getCompileSdk" }
        val setter = android.javaClass.methods.firstOrNull {
            it.name == "setCompileSdk" && it.parameterTypes.size == 1
        } ?: return@afterEvaluate
        val current = getter?.invoke(android) as? Int ?: 0
        if (current < 36) setter.invoke(android, 36)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

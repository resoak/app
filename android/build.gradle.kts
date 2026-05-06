allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val rootBuildDir = rootProject.layout.projectDirectory.dir("../build")
rootProject.layout.buildDirectory.value(rootBuildDir)

subprojects {
    val subproject = this
    subproject.layout.buildDirectory.value(rootBuildDir.dir(subproject.name))

    subproject.afterEvaluate {
        val androidExtension = subproject.extensions.findByName("android")
        if (androidExtension != null) {
            // 使用 layout.projectDirectory 以確保在 KTS 中正確引用路徑
            val manifestFile = subproject.layout.projectDirectory.file("src/main/AndroidManifest.xml").asFile
            if (manifestFile.exists()) {
                val content = manifestFile.readText()
                if (content.contains("package=\"")) {
                    // 使用 Java Pattern 避開部分環境下 Kotlin Regex 的 Serializable 衝突問題
                    val pattern = java.util.regex.Pattern.compile("package=\"([^\"]+)\"")
                    val matcher = pattern.matcher(content)
                    
                    if (matcher.find()) {
                        val pkgName = matcher.group(1)
                        
                        // 1. 強制設置 Namespace，確保與原 package 名稱一致以維持 R class 相容性
                        try {
                            val setNS = androidExtension.javaClass.getMethod("setNamespace", String::class.java)
                            val getNS = androidExtension.javaClass.getMethod("getNamespace")
                            if (getNS.invoke(androidExtension) == null) {
                                setNS.invoke(androidExtension, pkgName)
                            }
                        } catch (e: Exception) {
                            // 忽略反射錯誤
                        }

                        // 2. 移除 Manifest 中的 package 屬性 (這是 AGP 8.0+ 的硬性要求)
                        // 雖然修改 pub-cache 並非最佳實踐，但在不升級庫版本的情況下這是唯一的解決方案
                        try {
                            val updatedContent = content.replace("package=\"$pkgName\"", "")
                            manifestFile.writeText(updatedContent)
                            println("AGP 8.0 Fix: Removed package '$pkgName' from ${subproject.name} manifest.")
                        } catch (e: Exception) {
                            println("AGP 8.0 Warning: Failed to write to manifest of ${subproject.name}. If build fails, check write permissions.")
                        }
                    }
                }
            }
            
            // 額外保險：如果經過上述步驟仍未設置 namespace (例如無 manifest 的子項目)
            try {
                val getNS = androidExtension.javaClass.getMethod("getNamespace")
                val setNS = androidExtension.javaClass.getMethod("setNamespace", String::class.java)
                if (getNS.invoke(androidExtension) == null) {
                    val ns = "com.lecture_vault.generated.${subproject.name.replace("-", "_")}"
                    setNS.invoke(androidExtension, ns)
                }
            } catch (e: Exception) {}
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

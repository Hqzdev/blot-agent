plugins { alias(libs.plugins.spring.boot) }
dependencies {
    implementation(project(":application"))
    implementation(project(":infrastructure"))
    implementation(platform("org.springframework.boot:spring-boot-dependencies:${libs.versions.spring.boot.get()}"))
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation(libs.jackson)
    testImplementation(project(":client"))
}

tasks.withType<JavaExec>().configureEach { jvmArgs("--enable-native-access=ALL-UNNAMED") }

tasks.named<JavaExec>("bootRun") {
    val operatorEnv = rootProject.file("../.env")
    if (operatorEnv.isFile && !System.getenv().containsKey("BLOT_ENV_FILE")) {
        environment("BLOT_ENV_FILE", operatorEnv.absolutePath)
    }
}

tasks.named<org.springframework.boot.gradle.tasks.bundling.BootJar>("bootJar") {
    archiveFileName.set("blot-backend.jar")
}

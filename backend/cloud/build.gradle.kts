plugins { alias(libs.plugins.spring.boot) }
dependencies {
    implementation(project(":application"))
    implementation(project(":infrastructure"))
    implementation(platform("org.springframework.boot:spring-boot-dependencies:${libs.versions.spring.boot.get()}"))
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation(libs.jackson)
}
tasks.named<org.springframework.boot.gradle.tasks.bundling.BootJar>("bootJar") {
    archiveFileName.set("blot-cloud.jar")
}
tasks.withType<JavaExec>().configureEach { jvmArgs("--enable-native-access=ALL-UNNAMED") }

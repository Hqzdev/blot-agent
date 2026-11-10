plugins {
 java
 application
}
group = "com.blot.windows"
version = "1.0-SNAPSHOT"
repositories { mavenCentral() }
java { toolchain { languageVersion = JavaLanguageVersion.of(25) } }
application { mainClass.set("com.blot.windows.Launcher") }
sourceSets {
 main { java.srcDirs("../../../backend/core/src/main/java", "../../../backend/client/src/main/java") }
 test { java.srcDir("../../../backend/client/src/test/java"); resources.srcDir("../../../fixtures/v3") }
}
tasks.compileJava { include("com/blot/**", "dev/blot/core/v3/**", "dev/blot/client/**") }
tasks.withType<JavaCompile> { options.encoding = "UTF-8" }
dependencies {
 for (module in listOf("base", "graphics", "controls")) {
  implementation("org.openjfx:javafx-$module:21.0.6:win")
 }
 implementation("com.fasterxml.jackson.core:jackson-databind:2.20.0")
 implementation("com.fasterxml.jackson.datatype:jackson-datatype-jsr310:2.20.0")
 testImplementation("org.junit.jupiter:junit-jupiter:5.13.4")
 testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.13.4")
}

tasks.test { useJUnitPlatform() }

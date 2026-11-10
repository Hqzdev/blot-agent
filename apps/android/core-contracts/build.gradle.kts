plugins { `java-library` }
java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
sourceSets {
 main { java.srcDirs(rootProject.file("../../backend/core/src/main/java"), rootProject.file("../../backend/client/src/main/java")) }
 test { java.srcDir(rootProject.file("../../backend/client/src/test/java")); resources.srcDir(rootProject.file("../../fixtures/v3")) }
}
tasks.compileJava { include("dev/blot/core/v3/**", "dev/blot/client/**") }
tasks.test { useJUnitPlatform() }
dependencies {
 api("com.fasterxml.jackson.core:jackson-databind:2.20.0")
 implementation("com.fasterxml.jackson.datatype:jackson-datatype-jsr310:2.20.0")
 testImplementation("org.junit.jupiter:junit-jupiter:5.13.4")
 testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.13.4")
}

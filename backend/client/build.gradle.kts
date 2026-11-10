java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
sourceSets.main { java.srcDir("../core/src/main/java/dev/blot/core/v3") }
sourceSets.test { resources.srcDir(rootProject.file("../fixtures/v3")) }
configure<com.diffplug.gradle.spotless.SpotlessExtension> {
    java { target("src/**/*.java") }
}
dependencies {
    api(libs.jackson)
    implementation("com.fasterxml.jackson.datatype:jackson-datatype-jsr310:2.20.0")
}

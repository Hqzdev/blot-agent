pluginManagement { repositories { gradlePluginPortal(); mavenCentral() } }
rootProject.name = "blot-backend"
include("core", "application", "infrastructure", "api", "cloud")

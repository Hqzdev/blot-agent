plugins { id("com.android.application") }
android {
 namespace = "com.blot.android"
 compileSdk = 37
 defaultConfig { applicationId = "com.blot.android"; minSdk = 36; targetSdk = 37; versionCode = 1; versionName = "1.0" }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
dependencies { implementation(project(":core-contracts")) }

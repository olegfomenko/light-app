import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

// Real release signing when app/keystore.properties exists (gitignored).
// Without it, `assembleRelease` falls back to the debug key so a locally built
// APK still installs on a dev device — but `bundleRelease` refuses to (see the
// guard below), because a debug-signed bundle is useless to Play.
val keystorePropsFile = rootProject.file("app/keystore.properties")
val hasReleaseKeystore = keystorePropsFile.exists()

android {
    namespace = "app.light.wallet"
    compileSdk = 36
    // Pinned so AGP auto-installs the right NDK on first build (licenses
    // are accepted once via Android Studio); r27+ needed for 16KB pages.
    ndkVersion = "27.2.12479018"

    defaultConfig {
        applicationId = "app.light.wallet"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        ndk {
            // arm64 covers modern devices and the emulator on Apple Silicon.
            abiFilters += listOf("arm64-v8a")
        }
    }

    if (hasReleaseKeystore) {
        val props = Properties().apply { keystorePropsFile.inputStream().use { load(it) } }
        signingConfigs {
            create("release") {
                storeFile = rootProject.file(props.getProperty("storeFile"))
                storePassword = props.getProperty("storePassword")
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // R8: strips unused code (Compose tooling, unreached branches) and
            // removes the debug-mode runtime checks that make debug builds slow.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Sign with the real release key when app/keystore.properties exists;
            // otherwise fall back to the debug key so a locally built release APK
            // still installs on a dev device. Provide a real keystore before
            // distributing to anyone else (the debug key is public).
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release")
            else signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// ---------------------------------------------------------------------------
// Rust core: build liblightcore.so + regenerate the UniFFI Kotlin bindings as
// part of every Gradle build, so cloning the repo and pressing Run in Android
// Studio is enough. Needs rustup + cargo-ndk + protoc on the host — run
// scripts/bootstrap.sh once if they are missing.
// ---------------------------------------------------------------------------
val buildRustCore = tasks.register<Exec>("buildRustCore") {
    group = "build"
    description = "Compile the Rust core for Android and regenerate UniFFI Kotlin bindings"

    workingDir = rootProject.projectDir
    commandLine("bash", "scripts/build-rust.sh")

    inputs.files(fileTree("${rootProject.projectDir}/core/src"))
    inputs.file("${rootProject.projectDir}/core/Cargo.toml")
    inputs.file("${rootProject.projectDir}/scripts/build-rust.sh")
    outputs.dir("${projectDir}/src/main/jniLibs")
    outputs.dir("${projectDir}/src/main/java/app/light/wallet/core")

    doFirst {
        // Android Studio launches Gradle with a minimal PATH; make sure
        // cargo (rustup) and protoc (homebrew) are reachable, and hand the
        // Gradle-managed NDK to cargo-ndk.
        val home = System.getProperty("user.home")
        environment(
            "PATH",
            "$home/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:" + System.getenv("PATH")
        )
        environment("ANDROID_NDK_HOME", android.ndkDirectory.absolutePath)
    }
}

tasks.named("preBuild") {
    dependsOn(buildRustCore)
}

// A Play upload must never be debug-signed: Google rejects the bundle outright,
// and the public debug key could never be rotated into a real upload key. Fail
// here rather than after a 17 MB upload.
tasks.matching { it.name == "bundleRelease" }.configureEach {
    doFirst {
        if (!hasReleaseKeystore) {
            throw GradleException(
                "bundleRelease needs your own upload key — app/keystore.properties is missing.\n" +
                    "Create the keystore (you choose and keep the password):\n" +
                    "  keytool -genkeypair -v -keystore ~/lightapp-upload.jks \\\n" +
                    "    -alias upload -keyalg RSA -keysize 4096 -validity 10000\n" +
                    "then write app/keystore.properties (git-ignored) with storeFile / " +
                    "storePassword / keyAlias / keyPassword.",
            )
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.kotlinx.coroutines.android)
    // QR rendering for receive/invoice sheets
    implementation("com.google.zxing:core:3.5.3")
    // Required by the UniFFI-generated bindings
    implementation("net.java.dev.jna:jna:5.14.0@aar")
    debugImplementation(libs.androidx.ui.tooling)
}

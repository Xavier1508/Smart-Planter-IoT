plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStoreFile = System.getenv("MOSS_KEYSTORE_FILE")
val releaseStorePassword = System.getenv("MOSS_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("MOSS_KEY_ALIAS")
val releaseKeyPassword = System.getenv("MOSS_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "io.github.xavier1508.smart_planter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.xavier1508.smart_planter"
        manifestPlaceholders["appLabel"] = "Tunas · Smart Planter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("mossRelease") {
            if (hasReleaseSigning) {
                storeFile = file(releaseStoreFile!!)
                storeType = "PKCS12"
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            // Development builds keep the same application id as release so the
            // local-only app has one identity. A debug APK cannot replace a
            // release build signed with the stable key (signature mismatch).
        }
        release {
            // Never sign a distributable APK with an ephemeral debug key.
            signingConfig = signingConfigs.getByName("mossRelease")
        }
    }
}

val verifyReleaseSigning = tasks.register("verifyMossReleaseSigning") {
    doLast {
        check(hasReleaseSigning) {
            "A stable release keystore and all MOSS_KEYSTORE_* / MOSS_KEY_* environment variables are required."
        }
        check(file(releaseStoreFile!!).isFile) { "Release keystore file does not exist." }
    }
}

tasks.configureEach {
    if (name.startsWith("pre") && name.endsWith("ReleaseBuild")) {
        dependsOn(verifyReleaseSigning)
    }
}

dependencies {
    // NotificationCompat and ContextCompat are used by the local notification
    // channels (no Firebase or cloud SDK).
    implementation("androidx.core:core-ktx:1.13.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

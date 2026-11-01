plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") apply false
}

// Only the private tester variant needs Firebase. A production build can be
// built without a Firebase configuration or the App Distribution SDK.
val firebaseConfig = file("google-services.json")
if (firebaseConfig.isFile) {
    apply(plugin = "com.google.gms.google-services")
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

    flavorDimensions += "distribution"
    productFlavors {
        create("production") { dimension = "distribution" }
        create("beta") { dimension = "distribution" }
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
            // A disposable local preview must not replace the signed beta app.
            applicationIdSuffix = ".preview"
            versionNameSuffix = "-preview"
            manifestPlaceholders["appLabel"] = "Tunas · Pratinjau"
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

val verifyTesterFirebase = tasks.register("verifyMossTesterFirebase") {
    doLast {
        check(firebaseConfig.isFile) {
            "The tester variant requires android/app/google-services.json for the registered Android app."
        }
    }
}

tasks.configureEach {
    if (name.startsWith("pre") && name.endsWith("ReleaseBuild")) {
        dependsOn(verifyReleaseSigning)
    }
    if (name.startsWith("preBeta") && name.endsWith("Build")) {
        dependsOn(verifyTesterFirebase)
    }
}

dependencies {
    // The self-update SDK must never be included in a Google Play build.
    add("betaImplementation", "com.google.firebase:firebase-appdistribution:16.0.0-beta21")
    // Its installer activity inherits the application theme and needs AppCompat.
    add("betaImplementation", "androidx.appcompat:appcompat:1.7.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

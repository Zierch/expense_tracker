import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing
//
// Credentials live in android/key.properties, which is git-ignored. See
// README.md -> "Building a release APK".
//
// Why there is deliberately NO fallback to the debug keystore:
// the Flutter template ships `signingConfig = signingConfigs.getByName("debug")`
// for release builds. That is tolerable for a private build, but this app is
// handed to other people as an APK. Android refuses to install an update whose
// signer differs, and the debug keystore is per-machine and recreatable, so a
// debug-signed APK strands its users the first time it is rebuilt from anywhere
// else: they must uninstall, which deletes their financial database. Removing
// that one line is what actually closes the hole; the checks below only make
// the failure legible and early. Without a configured key a release build now
// produces an *unsigned* artifact, which is useless by construction.
// ---------------------------------------------------------------------------

val requiredSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()

// Anything non-null here means "a release artifact cannot be signed".
var releaseSigningProblem: String? = null
if (!keystorePropertiesFile.exists()) {
    releaseSigningProblem = "android/key.properties does not exist."
} else {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    val blank = requiredSigningKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (blank.isNotEmpty()) {
        releaseSigningProblem = "android/key.properties has no value for: ${blank.joinToString(", ")}."
    }
}
val hasReleaseSigning = releaseSigningProblem == null

val releaseSigningErrorMessage: String = """
    A release build was requested, but this project has no signing key, so the
    result could not be installed over an existing install or shared with anyone.

    ${releaseSigningProblem ?: ""}

    To fix it, create a keystore and copy android/key.properties.example to
    android/key.properties with your own credentials. See README.md ->
    "Building a release APK".
""".trimIndent()

// Fast path: catches the ordinary `flutter build apk --release` immediately,
// before Gradle does any work, so the message arrives in seconds instead of
// after a full compile.
if (gradle.startParameter.taskNames.any { it.contains("Release") } && !hasReleaseSigning) {
    throw GradleException(releaseSigningErrorMessage)
}

android {
    namespace = "com.zierch.expense_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.zierch.expense_tracker"
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
        if (hasReleaseSigning) {
            create("release") {
                // All four were verified non-blank above.
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            // Deliberately no debug-keystore fallback: see the header comment.
        }
        // The `profile` build type that Flutter adds is intentionally left on the
        // debug keystore. It exists for `flutter run --profile` performance work
        // and is never a distribution artifact, so demanding a release key for it
        // would only break the development loop with no gain.
    }
}

// Authoritative guard: the fast path above only fires when the requested task
// *name* happens to contain "Release". `gradlew assemble`, `gradlew build`,
// `gradlew aR`, IDE builds and camel-case abbreviations all reach the release
// variant without ever naming it, so the check that actually holds runs on the
// packaging task itself. That task exists precisely when a release artifact is
// about to be produced, whichever route the build took to get there.
tasks.configureEach {
    if (name.startsWith("package") && name.contains("Release")) {
        doFirst {
            if (!hasReleaseSigning) {
                throw GradleException(releaseSigningErrorMessage)
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

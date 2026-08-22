import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La clé de signature ne vit jamais dans le dépôt.
//
// `android/key.properties` la désigne, et ce fichier est ignoré par git au
// même titre que le magasin de clés lui-même. Sans lui, la compilation se
// fait avec la clé de débogage : on peut donc construire et essayer
// l'application sans rien détenir, ce qui est exactement ce qu'il faut pour
// une intégration continue ou pour quelqu'un qui reprend le dépôt.
//
// Un APK signé en débogage s'installe et fonctionne, mais il ne peut pas
// mettre à jour un APK signé avec la vraie clé : Android refuse de remplacer
// une application par une autre signature. C'est pour ça que la distribution
// aux commerçants attend la vraie clé.
val proprietesDeSignature = Properties().apply {
    val fichier = rootProject.file("key.properties")
    if (fichier.exists()) fichier.inputStream().use { load(it) }
}
val signatureDisponible = proprietesDeSignature.containsKey("storeFile")

android {
    namespace = "bf.commerce.carnet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "bf.commerce.carnet"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signatureDisponible) {
            create("diffusion") {
                storeFile = file(proprietesDeSignature.getProperty("storeFile"))
                storePassword = proprietesDeSignature.getProperty("storePassword")
                keyAlias = proprietesDeSignature.getProperty("keyAlias")
                keyPassword = proprietesDeSignature.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (signatureDisponible) {
                signingConfigs.getByName("diffusion")
            } else {
                // Faute de clé, celle de débogage : l'application se compile
                // et s'installe, et rien ne se fait passer pour signé.
                signingConfigs.getByName("debug")
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

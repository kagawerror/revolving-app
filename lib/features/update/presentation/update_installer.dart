import 'package:ota_update/ota_update.dart';

/// Thin wrapper over the ota_update plugin: downloads the APK over HTTPS and
/// launches the Android system installer, streaming progress events.
///
/// [usePackageInstaller] selects the modern session-based `PackageInstaller`
/// path instead of the deprecated `ACTION_INSTALL_PACKAGE` intent. The session
/// path streams the downloaded bytes straight into the installer and does NOT
/// resolve a `FileProvider` — avoiding the unconfigured-authority crash that
/// killed the app at 100% on the intent path — and it is the supported install
/// route on Android 12+/14+. It does require the `InstallResultReceiver`
/// declared in AndroidManifest.xml to deliver the final install result.
class UpdateInstaller {
  const UpdateInstaller();

  Stream<OtaEvent> downloadAndInstall(String apkUrl) {
    return OtaUpdate().execute(
      apkUrl,
      destinationFilename: 'rev_app-update.apk',
      usePackageInstaller: true,
    );
  }
}

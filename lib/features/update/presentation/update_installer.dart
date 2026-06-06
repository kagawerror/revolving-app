import 'package:ota_update/ota_update.dart';

/// Thin wrapper over the ota_update plugin: downloads the APK over HTTPS and
/// launches the Android system installer, streaming progress events.
class UpdateInstaller {
  const UpdateInstaller();

  Stream<OtaEvent> downloadAndInstall(String apkUrl) {
    return OtaUpdate().execute(apkUrl, destinationFilename: 'rev_app-update.apk');
  }
}

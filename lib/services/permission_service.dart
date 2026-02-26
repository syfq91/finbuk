import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  Future<bool> requestStoragePermission() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 30) {
      // Android 11+ requires MANAGE_EXTERNAL_STORAGE for custom paths
      var status = await Permission.manageExternalStorage.status;
      if (status.isGranted) return true;

      status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    } else {
      // Legacy storage for Android 10 and below
      var status = await Permission.storage.status;
      if (status.isGranted) return true;

      if (status.isDenied || status.isLimited) {
        status = await Permission.storage.request();
      }

      return status.isGranted;
    }
  }

  Future<bool> hasStoragePermission() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 30) {
      return await Permission.manageExternalStorage.isGranted;
    } else {
      return await Permission.storage.isGranted;
    }
  }
}

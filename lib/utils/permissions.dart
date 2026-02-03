import 'dart:io';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:device_info_plus/device_info_plus.dart';

class Permissions {
  static Future<bool> requestStoragePermission() async {
    if (Platform.isIOS) return true;
    if (!Platform.isAndroid) return true;
    
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    
    if (sdkInt >= 33) {
      final photos = await ph.Permission.photos.request();
      final audio = await ph.Permission.audio.request();
      final videos = await ph.Permission.videos.request();
      return photos.isGranted || audio.isGranted || videos.isGranted;
    } else if (sdkInt >= 30) {
      final manageStorage = await ph.Permission.manageExternalStorage.request();
      if (manageStorage.isGranted) return true;
      
      final storage = await ph.Permission.storage.request();
      return storage.isGranted;
    } else {
      final storage = await ph.Permission.storage.request();
      return storage.isGranted;
    }
  }

  static Future<bool> requestAudioPermission() async {
    final status = await ph.Permission.audio.request();
    return status.isGranted;
  }

  static Future<bool> requestNotificationPermission() async {
    final status = await ph.Permission.notification.request();
    return status.isGranted;
  }

  static Future<bool> hasStoragePermission() async {
    if (Platform.isIOS) return true;
    if (!Platform.isAndroid) return true;
    
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    
    if (sdkInt >= 33) {
      final photos = await ph.Permission.photos.status;
      final audio = await ph.Permission.audio.status;
      final videos = await ph.Permission.videos.status;
      return photos.isGranted || audio.isGranted || videos.isGranted;
    } else if (sdkInt >= 30) {
      final manageStorage = await ph.Permission.manageExternalStorage.status;
      if (manageStorage.isGranted) return true;
      
      final storage = await ph.Permission.storage.status;
      return storage.isGranted;
    } else {
      final storage = await ph.Permission.storage.status;
      return storage.isGranted;
    }
  }

  static Future<bool> hasAudioPermission() async {
    final status = await ph.Permission.audio.status;
    return status.isGranted;
  }

  static Future<bool> hasNotificationPermission() async {
    final status = await ph.Permission.notification.status;
    return status.isGranted;
  }

  static Future<bool> requestAllPermissions() async {
    final storage = await requestStoragePermission();
    final audio = await requestAudioPermission();
    final notification = await requestNotificationPermission();
    
    return storage && audio && notification;
  }

  static Future<bool> hasAllPermissions() async {
    final storage = await hasStoragePermission();
    final audio = await hasAudioPermission();
    final notification = await hasNotificationPermission();
    
    return storage && audio && notification;
  }

  static Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }
}

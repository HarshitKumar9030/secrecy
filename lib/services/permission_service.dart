import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  static Future<int> _getAndroidVersion() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      return 33; // Default to Android 13 if detection fails
    }
  }

  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  static Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  static Future<bool> requestStoragePermission() async {
    final androidVersion = await _getAndroidVersion();
    
    if (androidVersion >= 33) {
      // Android 13+ - Use granular media permissions
      final results = await [
        Permission.photos,
        Permission.videos,
      ].request();
      
      return results[Permission.photos]?.isGranted == true ||
             results[Permission.videos]?.isGranted == true;
    } else {
      // Android 12 and below - Use legacy storage permission
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  static Future<bool> requestPhotosPermission() async {
    final androidVersion = await _getAndroidVersion();
    
    if (androidVersion >= 33) {
      // Android 13+ - Request READ_MEDIA_IMAGES
      final status = await Permission.photos.request();
      return status.isGranted;
    } else {
      // Android 12 and below - Request storage permission
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  static Future<bool> requestNotificationPermission() async {
    final androidVersion = await _getAndroidVersion();
    
    if (androidVersion >= 33) {
      // Android 13+ - POST_NOTIFICATIONS is a runtime permission
      final status = await Permission.notification.request();
      return status.isGranted;
    } else {
      // Android 12 and below - notifications are granted at install time
      return true;
    }
  }

  static Future<bool> requestCallPermissions() async {
    final results = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final hasBasicPermissions = results[Permission.camera]?.isGranted == true &&
                               results[Permission.microphone]?.isGranted == true;
    
    // Also request notification permission for incoming call alerts
    await requestNotificationPermission();
    
    return hasBasicPermissions;
  }

  static Future<bool> requestMediaPermissions() async {
    final results = await [
      Permission.camera,
    ].request();
    
    final hasCamera = results[Permission.camera]?.isGranted == true;
    final hasStorage = await requestStoragePermission();
    
    return hasCamera && hasStorage;
  }

  static Future<bool> hasCallPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final microphoneStatus = await Permission.microphone.status;
    
    return cameraStatus.isGranted && microphoneStatus.isGranted;
  }

  static Future<bool> hasMediaPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final androidVersion = await _getAndroidVersion();
    
    bool hasStorageAccess;
    if (androidVersion >= 33) {
      // Android 13+ - Check granular permissions
      final photosStatus = await Permission.photos.status;
      final videosStatus = await Permission.videos.status;
      hasStorageAccess = photosStatus.isGranted || videosStatus.isGranted;
    } else {
      // Android 12 and below - Check legacy storage permission
      final storageStatus = await Permission.storage.status;
      hasStorageAccess = storageStatus.isGranted;
    }
    
    return cameraStatus.isGranted && hasStorageAccess;
  }

  static Future<bool> hasNotificationPermission() async {
    final androidVersion = await _getAndroidVersion();
    
    if (androidVersion >= 33) {
      final status = await Permission.notification.status;
      return status.isGranted;
    } else {
      // Pre-Android 13 - notifications are granted at install time
      return true;
    }
  }

  static void showPermissionDialog(BuildContext context, String permission) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Color(0xFFFF6B6B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Permission Required',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2F3437),
                ),
              ),
            ],
          ),
          content: Text(
            'This app needs $permission permission to function properly. Please grant permission in settings.',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF9B9A97),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF9B9A97),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text(
                'Settings',
                style: TextStyle(
                  color: Color(0xFF2F3437),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

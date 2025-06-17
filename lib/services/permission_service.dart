import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class PermissionService {
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  static Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  static Future<bool> requestStoragePermission() async {
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  static Future<bool> requestPhotosPermission() async {
    final status = await Permission.photos.request();
    return status.isGranted;
  }

  static Future<bool> requestCallPermissions() async {
    final results = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    return results[Permission.camera]?.isGranted == true &&
           results[Permission.microphone]?.isGranted == true;
  }

  static Future<bool> requestMediaPermissions() async {
    final results = await [
      Permission.camera,
      Permission.storage,
      Permission.photos,
    ].request();

    return results[Permission.camera]?.isGranted == true &&
           (results[Permission.storage]?.isGranted == true ||
            results[Permission.photos]?.isGranted == true);
  }

  static Future<bool> hasCallPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final microphoneStatus = await Permission.microphone.status;
    
    return cameraStatus.isGranted && microphoneStatus.isGranted;
  }

  static Future<bool> hasMediaPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final storageStatus = await Permission.storage.status;
    final photosStatus = await Permission.photos.status;
    
    return cameraStatus.isGranted && 
           (storageStatus.isGranted || photosStatus.isGranted);
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

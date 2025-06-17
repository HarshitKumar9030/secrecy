import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'dart:io' show Platform;

enum PermissionType { audio, video, audioVideo }

class VideoSDKPermissionService {
  // Check current permissions status
  static Future<Map<String, bool>> checkPermissions() async {
    Map<String, bool> permissions = {};
    
    try {
      if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
        // For WebRTC, we need to actually try to get media to check permissions
        try {
          // Try to get audio permission
          await webrtc.navigator.mediaDevices.getUserMedia({'audio': true});
          permissions['audio'] = true;
        } catch (e) {
          permissions['audio'] = false;
        }
        
        try {
          // Try to get video permission
          await webrtc.navigator.mediaDevices.getUserMedia({'video': true});
          permissions['video'] = true;
        } catch (e) {
          permissions['video'] = false;
        }
      } else {
        // For desktop, assume permissions are granted
        permissions['audio'] = true;
        permissions['video'] = true;
      }
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      permissions['audio'] = false;
      permissions['video'] = false;
    }
    
    return permissions;
  }
  
  // Request permissions
  static Future<Map<String, bool>> requestPermissions(PermissionType type) async {
    Map<String, bool> permissions = {};
    
    try {
      Map<String, dynamic> constraints = {};
      
      switch (type) {
        case PermissionType.audio:
          constraints = {'audio': true, 'video': false};
          break;
        case PermissionType.video:
          constraints = {'audio': false, 'video': true};
          break;
        case PermissionType.audioVideo:
          constraints = {'audio': true, 'video': true};
          break;
      }
      
      final stream = await webrtc.navigator.mediaDevices.getUserMedia(constraints);
      
      // If we got here, permissions were granted
      if (constraints['audio'] == true) {
        permissions['audio'] = true;
      }
      if (constraints['video'] == true) {
        permissions['video'] = true;
      }
      
      // Stop the tracks immediately since we only needed them for permission
      stream.getTracks().forEach((track) => track.stop());
      
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      if (type == PermissionType.audio || type == PermissionType.audioVideo) {
        permissions['audio'] = false;
      }
      if (type == PermissionType.video || type == PermissionType.audioVideo) {
        permissions['video'] = false;
      }
    }
    
    return permissions;
  }
  
  // Check and request permissions if needed
  static Future<bool> ensurePermissions(PermissionType type) async {
    final currentPermissions = await checkPermissions();
    
    bool needsAudio = (type == PermissionType.audio || type == PermissionType.audioVideo);
    bool needsVideo = (type == PermissionType.video || type == PermissionType.audioVideo);
    
    bool hasAudio = needsAudio ? (currentPermissions['audio'] ?? false) : true;
    bool hasVideo = needsVideo ? (currentPermissions['video'] ?? false) : true;
    
    if (hasAudio && hasVideo) {
      return true; // Already have all needed permissions
    }
    
    // Request missing permissions
    final requestedPermissions = await requestPermissions(type);
    
    bool audioOk = needsAudio ? (requestedPermissions['audio'] ?? false) : true;
    bool videoOk = needsVideo ? (requestedPermissions['video'] ?? false) : true;
    
    return audioOk && videoOk;
  }
}

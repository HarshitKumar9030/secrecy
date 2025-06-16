import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  // Option 1: Use default Firebase Storage (recommended)
  Future<String> uploadImageToFirebase(File imageFile, String folder) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No authenticated user');

    try {
      print('Uploading image to Firebase Storage...');
      final imageId = _uuid.v4();
      final ref = _storage.ref().child(folder).child('${user.uid}_$imageId.jpg');
      
      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
      final imageUrl = await snapshot.ref.getDownloadURL();
      print('Image uploaded successfully. URL: $imageUrl');
      
      return imageUrl;
    } catch (e) {
      print('Error uploading image to Firebase: $e');
      throw Exception('Failed to upload image: $e');
    }
  }

  // Option 2: Use external Google Cloud Storage bucket
  // Note: This requires additional setup with service account credentials
  /*
  Future<String> uploadImageToExternalBucket(File imageFile, String folder) async {
    // This would require:
    // 1. google_cloud package
    // 2. Service account credentials
    // 3. Manual authentication setup
    // 
    // Example implementation:
    // final storage = Storage(await clientViaServiceAccount(credentials, [StorageApi.CloudPlatformScope]));
    // final bucket = storage.bucket('secrecyd');
    // final object = bucket.object('$folder/${_uuid.v4()}.jpg');
    // await object.writeBytes(await imageFile.readAsBytes());
    // return 'gs://secrecyd/$folder/${object.name}';
    
    throw UnimplementedError('External bucket upload requires additional setup');
  }
  */

  // Profile image upload
  Future<String> uploadProfileImage(File imageFile) async {
    return uploadImageToFirebase(imageFile, 'profile_images');
  }

  // Chat image upload
  Future<String> uploadChatImage(File imageFile) async {
    return uploadImageToFirebase(imageFile, 'chat_images');
  }
}

# Firebase Storage Setup Guide

Since the bucket `secrecyd` is in a different Firebase account, here are your options:

## Option 1: Use Default Firebase Storage (Recommended)

1. **Enable Firebase Storage in Console:**
   - Go to https://console.firebase.google.com/project/secrecy-47166/storage
   - Click "Get Started" to enable Firebase Storage
   - Choose your storage location (preferably same as Firestore)
   - This will create the default bucket: `secrecy-47166.firebasestorage.app`

2. **Deploy Storage Rules:**
   ```bash
   firebase deploy --only storage
   ```

3. **Your app is already configured** to use Firebase Storage, so no code changes needed!

## Option 2: Use External Bucket `secrecyd` (Complex)

If you want to use the external bucket, you'll need to:

1. **Create Service Account:**
   - In the Firebase project that owns `secrecyd`
   - Download the service account JSON key

2. **Add Dependencies:**
   ```yaml
   dependencies:
     gcloud: ^0.8.9
   ```

3. **Replace Firebase Storage with Google Cloud Storage SDK:**
   - Use `gcloud` package instead of `firebase_storage`
   - Handle authentication manually
   - Update all image upload/download code

## Recommendation

**Use Option 1** - it's much simpler and provides the same functionality. The Firebase Storage SDK handles authentication, security rules, and integration seamlessly.

Your app's image upload functionality will work perfectly with the default Firebase Storage bucket once you enable it in the console.

## Current Status

- ✅ Storage rules are ready (`storage.rules`)
- ✅ App code is configured for Firebase Storage
- ⏳ Need to enable Firebase Storage in console
- ⏳ Deploy storage rules after enabling

## Next Steps

1. Enable Firebase Storage in the console
2. Run: `firebase deploy --only storage`
3. Test image upload in your app

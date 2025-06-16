@echo off
echo Setting up Firebase Storage for your current project...

echo.
echo 1. Deploying Firebase Storage rules to your current project...
firebase deploy --only storage

echo.
echo 2. Setting CORS configuration for your default Firebase Storage bucket...
echo [{"origin": ["*"], "method": ["GET", "HEAD", "PUT", "POST", "DELETE"], "maxAgeSeconds": 3600}] > cors.json
gsutil cors set cors.json gs://secrecy-47166.firebasestorage.app

echo.
echo 3. Testing Firebase Storage configuration...
firebase storage:buckets:list

echo.
echo Setup complete! Your Firebase Storage is now configured.
echo Default bucket: gs://secrecy-47166.firebasestorage.app
echo.
echo The app will use your default Firebase Storage bucket.
echo If you want to use the external bucket 'secrecyd', you'll need to:
echo 1. Create a service account with access to both projects
echo 2. Use Google Cloud Storage SDK directly instead of Firebase Storage
echo 3. Handle authentication manually between the projects

pause

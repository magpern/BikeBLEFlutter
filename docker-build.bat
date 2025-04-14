@echo off
echo Building APK with Docker...

REM Create a clean local.properties file just for the Docker build
echo sdk.dir=/home/flutter/Android/Sdk > android/local.properties.docker
echo flutter.sdk=/home/flutter/flutter >> android/local.properties.docker

REM Backup the original local.properties if it exists
if exist android\local.properties (
  copy /Y android\local.properties android\local.properties.backup
  copy /Y android\local.properties.docker android\local.properties
) else (
  copy /Y android\local.properties.docker android\local.properties
)

REM Run the Docker build
docker run --rm ^
  -v %cd%:/app ^
  -w /app ^
  -e DOCKER_CONTAINER=true ^
  -e FLUTTER_WINDOWS_PATH_FIX=true ^
  ghcr.io/magpern/bikebleflutter:latest ^
  flutter build apk --release

REM Restore the original local.properties
if exist android\local.properties.backup (
  copy /Y android\local.properties.backup android\local.properties
  del android\local.properties.backup
)

REM Delete the Docker-specific local.properties
del android\local.properties.docker

echo Build completed.
if exist build\app\outputs\flutter-apk\app-release.apk (
  echo APK created successfully at build\app\outputs\flutter-apk\app-release.apk
) else (
  echo Failed to create APK. Check the build logs above.
) 
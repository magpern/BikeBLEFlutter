#!/bin/bash
# Script to fix paths in Flutter artifacts during Docker build

# Define the Windows path prefix to replace
WINDOWS_PATH="D:\\\\nRF5_SDK\\\\projects\\\\satsbike_scanner"
DOCKER_PATH="/app"

# Check if we're running in Docker
if [ "$DOCKER_CONTAINER" == "true" ]; then
  echo "Running in Docker container, fixing paths..."
  
  # Create the patched flutter.bat
  cat > /home/flutter/flutter/bin/flutter-patched <<EOF
#!/bin/bash
# Patched Flutter script for Docker builds

# Set environment variables to override paths
export FLUTTER_BUILD_DIR=$DOCKER_PATH/build
export FLUTTER_APP_DIR=$DOCKER_PATH

# Run the original Flutter command
/home/flutter/flutter/bin/flutter "\$@"

# After building, fix any embedded paths in the output files
if [[ "\$*" == *"build apk"* || "\$*" == *"build appbundle"* ]]; then
  echo "Fixing paths in build artifacts..."
  find $DOCKER_PATH/build -type f -name "*.so" -o -name "*.dex" -o -name "*.jar" | while read file; do
    # Binary replacement of Windows paths with Docker paths
    sed -i "s|$WINDOWS_PATH|$DOCKER_PATH|g" "\$file" 2>/dev/null || true
  done
fi
EOF

  # Make the patched script executable
  chmod +x /home/flutter/flutter/bin/flutter-patched
  
  # Run with the patched script
  /home/flutter/flutter/bin/flutter-patched "$@"
else
  # Not in Docker, run the normal Flutter command
  flutter "$@"
fi 
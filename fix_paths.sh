#!/bin/bash

# Function to convert Windows paths to Linux paths
convert_path() {
    local file=$1
    if [ -f "$file" ]; then
        echo "Converting paths in $file"
        # First convert Windows drive letter to Linux path
        sed -i 's|D:/|/app/|g' "$file"
        sed -i 's|D:\\\\|/app/|g' "$file"
        # Then convert any remaining backslashes to forward slashes
        sed -i 's|\\\\|/|g' "$file"
    fi
}

# Set the build directory explicitly to /app/build
export GRADLE_OPTS="-Dorg.gradle.project.buildDir=/app/build -Dorg.gradle.java.home=/usr/lib/jvm/java-17-openjdk-amd64"

# Create symlink for build directory to avoid path issues
mkdir -p /home/flutter/build
ln -sf /app /home/flutter/app

# Process all gradle files that might contain Windows paths
find . -name "*.gradle" -o -name "*.gradle.kts" | while read file; do
    convert_path "$file"
done

# Process other build configuration files
convert_path "android/local.properties"
convert_path "android/gradle.properties"

# Export environment variables to influence path handling
export FLUTTER_BUILD_DIR=/app/build

# Execute the command passed to the script
exec "$@" 
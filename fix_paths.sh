#!/bin/bash

# Function to convert Windows paths to Linux paths
convert_path() {
    local file=$1
    if [ -f "$file" ]; then
        # First convert Windows drive letter to Linux path
        sed -i 's|D:/|/home/flutter/|g' "$file"
        # Then convert any remaining backslashes to forward slashes
        sed -i 's|\\|/|g' "$file"
        # Handle any Windows-style paths that might have been missed
        sed -i 's|D:\\|/home/flutter/|g' "$file"
    fi
}

# Convert paths in Gradle files
convert_path "android/settings.gradle.kts"
convert_path "android/build.gradle"

# Set the build directory to a Linux path
export GRADLE_OPTS="-Dorg.gradle.project.buildDir=/home/flutter/build -Dorg.gradle.java.home=/usr/lib/jvm/java-17-openjdk-amd64"

# Execute the command passed to the script
exec "$@" 
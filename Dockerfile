FROM ubuntu:22.04

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    openjdk-17-jdk \
    wget \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    && rm -rf /var/lib/apt/lists/*

# Set up new user
RUN useradd -ms /bin/bash flutter
USER flutter
WORKDIR /home/flutter

# Install Flutter
RUN git clone https://github.com/flutter/flutter.git -b stable
ENV PATH="/home/flutter/flutter/bin:${PATH}"
ENV FLUTTER_ROOT="/home/flutter/flutter"

# Install Android SDK
RUN mkdir -p /home/flutter/Android/Sdk
ENV ANDROID_SDK_ROOT="/home/flutter/Android/Sdk"
ENV PATH="${PATH}:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools"

# Download and install Android command line tools
RUN wget -q https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip -O cmdline-tools.zip \
    && mkdir -p /home/flutter/Android/Sdk/cmdline-tools \
    && unzip -q cmdline-tools.zip -d /home/flutter/Android/Sdk/cmdline-tools \
    && mv /home/flutter/Android/Sdk/cmdline-tools/cmdline-tools /home/flutter/Android/Sdk/cmdline-tools/latest \
    && rm cmdline-tools.zip

# Accept licenses and install Android SDK components
RUN yes | sdkmanager --licenses \
    && sdkmanager \
        "platform-tools" \
        "platforms;android-33" \
        "platforms;android-34" \
        "platforms;android-35" \
        "build-tools;33.0.2" \
        "build-tools;34.0.0" \
        "ndk;27.0.12077973"

# Pre-download Flutter dependencies
RUN flutter precache
RUN flutter doctor

# Configure Gradle to handle Windows paths
ENV FLUTTER_WINDOWS_PATH_FIX=true
ENV FLUTTER_BUILD_DIR=/home/flutter/build

# Create build directory
RUN mkdir -p /home/flutter/build

# Switch to root for script installation
USER root

# Create a script to fix Windows paths in Gradle files
COPY fix_paths.sh /home/flutter/fix_paths.sh
RUN chown flutter:flutter /home/flutter/fix_paths.sh && \
    chmod +x /home/flutter/fix_paths.sh

# Cleanup
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Switch back to flutter user
USER flutter

# Set the entrypoint to fix paths before running commands
ENTRYPOINT ["/home/flutter/fix_paths.sh"] 
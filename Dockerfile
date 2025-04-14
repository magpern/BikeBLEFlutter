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

# Create build directories (as root)
RUN mkdir -p /app && chown -R flutter:flutter /app

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

# Configure build environment to use standard non-Windows paths
ENV GRADLE_OPTS="-Dorg.gradle.project.buildDir=/app/build -Dfile.encoding=UTF-8 -Dorg.gradle.java.home.use.file.uri=true"
ENV DOCKER_CONTAINER="true"

# Create script to configure Gradle before building
RUN echo '#!/bin/bash\n\
# Create local.properties with the correct SDK path for Docker\n\
echo "sdk.dir=/home/flutter/Android/Sdk" > android/local.properties\n\
echo "flutter.sdk=/home/flutter/flutter" >> android/local.properties\n\
\n\
# Set environment variables for path handling\n\
export DOCKER_CONTAINER=true\n\
\n\
# Run the specified command\n\
exec "$@"' > /home/flutter/docker-entrypoint.sh && \
chmod +x /home/flutter/docker-entrypoint.sh

# Set the entrypoint script
ENTRYPOINT ["/home/flutter/docker-entrypoint.sh"] 
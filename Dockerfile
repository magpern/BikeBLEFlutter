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
    && rm -rf /var/lib/apt/lists/*

# Set up new user
RUN useradd -ms /bin/bash flutter
USER flutter
WORKDIR /home/flutter

# Install Flutter
RUN git clone https://github.com/flutter/flutter.git -b stable
ENV PATH="/home/flutter/flutter/bin:${PATH}"

# Pre-download Flutter dependencies
RUN flutter precache
RUN flutter doctor

# Switch back to root for cleanup
USER root
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Switch back to flutter user
USER flutter 
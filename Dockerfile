# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM rust:bullseye AS builder

# Build arguments for cross-compilation
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# Cross-compilation tools
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    cmake \
    libclang-dev \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    crossbuild-essential-armhf && \
    rm -rf /var/lib/apt/lists/*

# Add Rust target for ARM
RUN rustup target add armv7-unknown-linux-gnueabihf

# Install bindgen (required by aws-lc-sys)
RUN cargo install bindgen-cli

WORKDIR /builder

# Copy all source files
COPY . .

# Set cross-compilation environment
ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc \
    CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++ \
    AR_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-ar \
    CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_AR=arm-linux-gnueabihf-ar \
    PKG_CONFIG_ALLOW_CROSS=1 \
    BINDGEN_EXTRA_CLANG_ARGS="--sysroot=/usr/arm-linux-gnueabihf"

# Compile binary for ARM v7
RUN cargo build -p komodo_periphery --release --target armv7-unknown-linux-gnueabihf

# Strip binary with ARM strip tool
RUN arm-linux-gnueabihf-strip /builder/target/armv7-unknown-linux-gnueabihf/release/periphery

# Runtime Image - IMPORTANT: must specify platform for QEMU
FROM --platform=$TARGETPLATFORM debian:bullseye-slim

ARG TARGETPLATFORM

# Install base dependencies first
RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    libssl1.1 \
    curl \
    gnupg \
    lsb-release

# Add Docker repository for ARM
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=armhf signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bullseye stable" > /etc/apt/sources.list.d/docker.list

# Install Docker CLI and Docker Compose
RUN apt-get update && \
    apt-get install -y \
    docker-ce-cli \
    docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# Copy binary from builder stage
COPY --from=builder /builder/target/armv7-unknown-linux-gnueabihf/release/periphery /usr/local/bin/periphery

WORKDIR /app

ENTRYPOINT ["periphery"]
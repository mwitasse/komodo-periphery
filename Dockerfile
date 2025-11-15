# syntax=docker/dockerfile:1
# Build on native platform, cross-compile for target
FROM --platform=$BUILDPLATFORM rust:bullseye AS builder

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

# Intermediate stage: Download everything on native platform
FROM --platform=$BUILDPLATFORM alpine:latest AS downloader

RUN apk add --no-cache curl

# Download Docker CLI for ARM v7 (latest version 29.0.1)
RUN curl -fsSL https://download.docker.com/linux/static/stable/armhf/docker-29.0.1.tgz -o /tmp/docker.tgz && \
    tar xzf /tmp/docker.tgz -C /tmp && \
    chmod +x /tmp/docker/docker

# Download Docker Compose for ARM v7 (latest version v2.40.3)
RUN mkdir -p /tmp/cli-plugins && \
    curl -fsSL https://github.com/docker/compose/releases/download/v2.40.3/docker-compose-linux-armv7 -o /tmp/cli-plugins/docker-compose && \
    chmod +x /tmp/cli-plugins/docker-compose

# Final runtime - use pre-built ARM image that already has everything
FROM arm32v7/debian:bullseye-slim

# Copy Docker binaries from downloader (no apt-get needed!)
COPY --from=downloader /tmp/docker/docker /usr/local/bin/
COPY --from=downloader /tmp/cli-plugins /usr/local/lib/docker/cli-plugins/

# Copy periphery binary
COPY --from=builder /builder/target/armv7-unknown-linux-gnueabihf/release/periphery /usr/local/bin/periphery

WORKDIR /app

CMD ["periphery"]
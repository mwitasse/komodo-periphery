# syntax=docker/dockerfile:1
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

# Install bindgen
RUN cargo install bindgen-cli

WORKDIR /builder

# Copy source files
COPY . .

# Cross-compilation environment
ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc \
    CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++ \
    AR_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-ar \
    CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_AR=arm-linux-gnueabihf-ar \
    PKG_CONFIG_ALLOW_CROSS=1 \
    BINDGEN_EXTRA_CLANG_ARGS="--sysroot=/usr/arm-linux-gnueabihf"

# Build binary for ARM v7
RUN cargo build -p komodo_periphery --release --target armv7-unknown-linux-gnueabihf

# Strip binary
RUN arm-linux-gnueabihf-strip /builder/target/armv7-unknown-linux-gnueabihf/release/periphery

# Download Docker binaries on native platform
FROM --platform=$BUILDPLATFORM alpine:latest AS downloader

RUN apk add --no-cache curl

# Download Docker CLI 29.0.1 for ARM v7
RUN curl -fsSL https://download.docker.com/linux/static/stable/armhf/docker-29.0.1.tgz -o /tmp/docker.tgz && \
    tar xzf /tmp/docker.tgz -C /tmp

# Download Docker Compose v2.40.3 for ARM v7
RUN mkdir -p /tmp/cli-plugins && \
    curl -fsSL https://github.com/docker/compose/releases/download/v2.40.3/docker-compose-linux-armv7 -o /tmp/cli-plugins/docker-compose && \
    chmod +x /tmp/cli-plugins/docker-compose

# Download openssl binary for ARM v7
RUN curl -fsSL https://github.com/openssl/openssl/releases/download/openssl-3.0.15/openssl-3.0.15.tar.gz -o /tmp/openssl.tar.gz

# Runtime image - keep it minimal and close to official
FROM arm32v7/debian:bullseye-slim

# Copy periphery binary
COPY --from=builder /builder/target/armv7-unknown-linux-gnueabihf/release/periphery /usr/local/bin/periphery

# Copy Docker binaries
COPY --from=downloader /tmp/docker/docker /usr/local/bin/docker
COPY --from=downloader /tmp/cli-plugins/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

WORKDIR /root

# Match official image
CMD ["periphery"]
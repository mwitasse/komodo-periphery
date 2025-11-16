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

# Download Docker binaries and debs on native platform
FROM --platform=$BUILDPLATFORM debian:bullseye-slim AS downloader

RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

# Download Docker CLI 29.0.1 for ARM v7
RUN curl -fsSL https://download.docker.com/linux/static/stable/armhf/docker-29.0.1.tgz -o /tmp/docker.tgz && \
    tar xzf /tmp/docker.tgz -C /tmp

# Download Docker Compose v2.40.3 for ARM v7
RUN mkdir -p /tmp/cli-plugins && \
    curl -fsSL https://github.com/docker/compose/releases/download/v2.40.3/docker-compose-linux-armv7 -o /tmp/cli-plugins/docker-compose && \
    chmod +x /tmp/cli-plugins/docker-compose

# Download ARM Debian packages
RUN mkdir -p /tmp/debs && \
    cd /tmp/debs && \
    curl -fsSL http://ftp.debian.org/debian/pool/main/o/openssl/openssl_1.1.1w-0+deb11u2_armhf.deb -o openssl.deb && \
    curl -fsSL http://ftp.debian.org/debian/pool/main/o/openssl/libssl1.1_1.1.1w-0+deb11u2_armhf.deb -o libssl.deb && \
    curl -fsSL http://ftp.debian.org/debian/pool/main/c/ca-certificates/ca-certificates_20210119_all.deb -o ca-certificates.deb

# Runtime image
FROM arm32v7/debian:bullseye-slim

# Install packages from debs
COPY --from=downloader /tmp/debs/*.deb /tmp/
RUN dpkg -i /tmp/*.deb && rm /tmp/*.deb

# Copy periphery binary
COPY --from=builder /builder/target/armv7-unknown-linux-gnueabihf/release/periphery /usr/local/bin/periphery

# Copy Docker binaries
COPY --from=downloader /tmp/docker/docker /usr/local/bin/docker
COPY --from=downloader /tmp/cli-plugins/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

# Set environment variables matching official image
ENV PERIPHERY_CONFIG_PATHS=/config
ENV PERIPHERY_PRIVATE_KEY=file:/config/keys/periphery.key

# Create config directory
RUN mkdir -p /config/keys

# Expose port
EXPOSE 8120

WORKDIR /root

# Match official image exactly
CMD ["periphery"]
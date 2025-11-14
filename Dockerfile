# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM rust:bullseye AS builder

# Build-Argumente für Cross-Compilation
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# Cross-Compilation Tools installieren
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    cmake \
    libclang-dev \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    crossbuild-essential-armhf && \
    rm -rf /var/lib/apt/lists/*

# Rust Target für ARM hinzufügen
RUN rustup target add armv7-unknown-linux-gnueabihf

# Bindgen installieren (wird von aws-lc-sys benötigt)
RUN cargo install bindgen-cli

WORKDIR /builder

# Alle Source-Dateien kopieren
COPY . .

# Cross-Compilation Environment setzen
ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc \
    CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++ \
    AR_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-ar \
    CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_AR=arm-linux-gnueabihf-ar \
    PKG_CONFIG_ALLOW_CROSS=1 \
    BINDGEN_EXTRA_CLANG_ARGS="--sysroot=/usr/arm-linux-gnueabihf"

# Binary kompilieren für ARM v7
RUN cargo build -p komodo_periphery --release --target armv7-unknown-linux-gnueabihf

# Optional: Binary strippen mit ARM strip tool
RUN arm-linux-gnueabihf-strip /builder/target/armv7-unknown-linux-gnueabihf/release/periphery

# Nichts kopieren, direkt aus dem Target-Verzeichnis verwenden

# Runtime Image
FROM debian:bullseye-slim

# Runtime dependencies
RUN apt-get update && \
    apt-get install -y ca-certificates libssl1.1 && \
    rm -rf /var/lib/apt/lists/*

# Binary aus Builder-Stage kopieren - heißt "periphery" nicht "komodo_periphery"!
COPY --from=builder /builder/target/armv7-unknown-linux-gnueabihf/release/periphery /usr/local/bin/periphery

WORKDIR /app

ENTRYPOINT ["periphery"]
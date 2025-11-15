# Docker Cross-Compilation Build Guide for Komodo Periphery

Guide for building an ARM v7 Docker image on macOS using Colima and QEMU.

## Prerequisites

- macOS
- Colima installed and running
- Docker CLI installed
- Git

## 1. Colima Setup

```bash
# Stop Colima (if running)
colima stop

# Start Colima with sufficient resources
colima start --cpu 4 --memory 8 --disk 100

# Check Docker context
docker context list
```

## 2. Set up QEMU for Cross-Platform Builds

```bash
# Install QEMU emulation for ARM
docker run --privileged --rm tonistiigi/binfmt --install all

# Create multi-platform builder
docker buildx create --name armbuilder --driver docker-container --use

# Initialize builder
docker buildx inspect armbuilder --bootstrap
```

## 3. Clone Repository

```bash
# Clone Komodo repository
git clone https://github.com/moghtech/komodo.git

# Change to directory
cd komodo
```

## 4. Create Dockerfile

Create a `Dockerfile` with the following content:

```dockerfile
# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM rust:bullseye AS builder

# Build arguments for cross-compilation
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# Install cross-compilation tools
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

# Optional: Strip binary with ARM strip tool
RUN arm-linux-gnueabihf-strip /builder/target/armv7-unknown-linux-gnueabihf/release/periphery

# Runtime Image
FROM debian:bullseye-slim

# Runtime dependencies including Docker and Docker Compose
RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    libssl1.1 \
    curl \
    gnupg \
    lsb-release && \
    # Add Docker repository
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=armhf signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bullseye stable" > /etc/apt/sources.list.d/docker.list && \
    # Install Docker
    apt-get update && \
    apt-get install -y \
    docker-ce-cli \
    docker-compose-plugin && \
    # Cleanup
    rm -rf /var/lib/apt/lists/*

# Copy binary from builder stage
COPY --from=builder /builder/target/armv7-unknown-linux-gnueabihf/release/periphery /usr/local/bin/periphery

WORKDIR /app

ENTRYPOINT ["periphery"]
```

## 5. Create .dockerignore (optional)

```bash
cat > .dockerignore << 'EOF'
target/
.git/
.gitignore
*.md
README.md
.env
.DS_Store
node_modules/
EOF
```

## 6. Build Image

```bash
# Build for ARM v7 (e.g. Raspberry Pi 2/3)
docker-buildx build --platform linux/arm/v7 -t komodo-periphery:armv7 --load .

# With build log for debugging
docker-buildx build --platform linux/arm/v7 --progress=plain -t komodo-periphery:armv7 --load . 2>&1 | tee build.log
```

**Note:** Build may take 10-30 minutes due to cross-compilation!

**Docker Version:** This image includes Docker CLI 29.0.1 and Docker Compose v2.40.3

## 7. Test Image

```bash
# Show image
docker images komodo-periphery

# Start container for testing
docker run -it komodo-periphery:armv7 --help

# Test with Docker socket access (periphery needs this at runtime)
docker run -v /var/run/docker.sock:/var/run/docker.sock komodo-periphery:armv7
```

## 8. Read Version from Cargo.toml

```bash
# Determine version
VERSION=$(grep "^version" Cargo.toml | head -1 | cut -d'"' -f2)
echo "Version: $VERSION"
```

## 9. Push to Docker Hub

```bash
# Login to Docker Hub
docker login

# Replace USERNAME with your Docker Hub username
USERNAME="yourusername"

# Tag image with version and Docker version
docker tag komodo-periphery:armv7 $USERNAME/komodo-periphery:$VERSION-armv7-docker29.0.1
docker tag komodo-periphery:armv7 $USERNAME/komodo-periphery:latest-armv7

# Push to Docker Hub
docker push $USERNAME/komodo-periphery:$VERSION-armv7-docker29.0.1
docker push $USERNAME/komodo-periphery:latest-armv7
```

## 10. Export Image (Alternative to Docker Hub)

```bash
# Export as TAR for manual transfer
docker save komodo-periphery:armv7 | gzip > komodo-periphery-armv7.tar.gz

# Copy to Raspberry Pi
scp komodo-periphery-armv7.tar.gz pi@raspberry-pi-ip:/home/pi/

# Load on Pi
ssh pi@raspberry-pi-ip
docker load -i komodo-periphery-armv7.tar.gz
```

## Running the Container

Since periphery needs Docker at runtime, always mount the Docker socket:

```bash
# Run with Docker socket
docker run -v /var/run/docker.sock:/var/run/docker.sock komodo-periphery:armv7

# With docker-compose.yml
services:
  periphery:
    image: komodo-periphery:armv7
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

## Troubleshooting

### TLS/Certificate Errors

```bash
# Restart Colima
colima stop
colima start --network-address
```

### "exec format error"

```bash
# Reinstall QEMU
docker run --privileged --rm tonistiigi/binfmt --install all

# Recreate builder
docker buildx rm armbuilder
docker buildx create --name armbuilder --driver docker-container --use
docker buildx inspect armbuilder --bootstrap
```

### Clear Build Cache

```bash
# Complete rebuild without cache
docker buildx build --no-cache --platform linux/arm/v7 -t komodo-periphery:armv7 --load .
```

### Clean up Local Images

```bash
# Show all komodo images
docker images | grep komodo

# Remove unused images
docker image prune -a
```

## Building for Other Architectures

```bash
# For ARM 64-bit (Raspberry Pi 4/5)
# Note: Adjust Docker repository arch in Dockerfile from 'armhf' to 'arm64'
docker buildx build --platform linux/arm64 -t komodo-periphery:arm64 --load .

# For AMD64 (standard x86_64)
# Note: Adjust Docker repository arch in Dockerfile from 'armhf' to 'amd64'
docker buildx build --platform linux/amd64 -t komodo-periphery:amd64 --load .
```

## Useful Commands

```bash
# Show all Docker buildx builders
docker buildx ls

# Remove builder
docker buildx rm armbuilder

# Show all images
docker images

# Remove specific image
docker rmi komodo-periphery:armv7

# Check Colima status
colima status

# Switch Docker context
docker context use colima
```

## Links

- [Komodo Repository](https://github.com/moghtech/komodo)
- [Docker Buildx Documentation](https://docs.docker.com/buildx/working-with-buildx/)
- [Colima GitHub](https://github.com/abiosoft/colima)
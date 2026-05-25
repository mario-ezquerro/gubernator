# Rule: Multi-Architecture Container Compilation

## Objective
Gubernator must be compatible with multiple CPU architectures to run seamlessly across Intel/AMD servers, macOS Apple Silicon (M1/M2/M3) development environments, and ARM-based edge devices like Raspberry Pi.

## Requirements

1. **Platform Targets:** All official Gubernator Docker images and deployable containers MUST support and compile for:
   - `linux/amd64` (Intel/AMD servers)
   - `linux/arm64` (macOS Apple Silicon, Raspberry Pi 4+, AWS Graviton)
   - `linux/arm/v7` (32-bit Raspberry Pi and other older ARM devices)

2. **Docker Buildx Usage:** Always document and use `docker buildx` for multi-platform builds. The recommended command for compiling all platforms without pushing to a registry (for validation/testing) is:
   ```bash
   docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t marioezquerro/gubernator:latest .
   ```
   To build, tag, and push the multi-architecture image directly to Docker Hub:
   ```bash
   docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t marioezquerro/gubernator:latest --push .
   ```

3. **CI/CD Pipeline Integration:** Ensure any automation or GitHub Actions workflows for building container images use setup-buildx-action and compile for all three target platforms.

4. **Local Development Builds:** Explain to developers on macOS Apple Silicon (M-series) that standard `docker build -t gbnt:latest .` will compile for ARM64 locally, but they should use buildx when sharing or deploying images meant for heterogeneous clusters.
